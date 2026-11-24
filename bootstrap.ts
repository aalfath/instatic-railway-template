/**
 * First-boot owner setup for the Railway template.
 *
 * Instatic's first-run endpoint (POST /admin/api/cms/setup) is public until an
 * owner exists, so whoever opens a fresh install first would become its owner.
 * This script starts Instatic on 127.0.0.1 only (the public port is not open
 * yet), runs the database migrations through it, and, if setup is still
 * needed, creates the owner from ADMIN_EMAIL / ADMIN_PASSWORD through the same
 * official endpoint. Then it stops the loopback instance. It exits non-zero
 * on any failure so the service never opens with setup still pending.
 */
const port = String(30000 + Math.floor(Math.random() * 20000))
const base = `http://127.0.0.1:${port}`
const prefix = '/admin/api/cms'
const log = (msg: string) => console.log(`[instatic-railway] ${msg}`)

// Overlapping Railway deploys can boot two copies at once: hold a Postgres
// advisory lock (polled, never blocking) while migrating and creating the owner.
const dbUrl = process.env.DATABASE_URL ?? ''
const isPg = dbUrl.startsWith('postgres:') || dbUrl.startsWith('postgresql:')
const LOCK_KEY = 731_015_151
let lockDb: InstanceType<typeof Bun.SQL> | null = null
if (isPg) {
  const lockDeadline = Date.now() + 300_000
  for (;;) {
    try {
      lockDb ??= new Bun.SQL(dbUrl, { max: 1 })
      const rows = await lockDb`select pg_try_advisory_lock(${LOCK_KEY}) as got`
      if (rows[0]?.got) break
      log('another deploy holds the first-boot lock; waiting')
    } catch (err) {
      log(`database not reachable yet (${err instanceof Error ? err.message : String(err)}); retrying`)
      try { await lockDb?.close() } catch {}
      lockDb = null
    }
    if (Date.now() > lockDeadline) {
      console.error('[instatic-railway] ERROR: could not reach Postgres or take the first-boot lock within 300 s')
      process.exit(1)
    }
    await Bun.sleep(2000)
  }
}

const server = Bun.spawn(['bun', 'run', 'server/index.ts'], {
  cwd: '/app',
  env: { ...process.env, HOST: '127.0.0.1', PORT: port },
  stdout: 'inherit',
  stderr: 'inherit',
})

async function stop(): Promise<void> {
  if (server.exitCode !== null) return
  server.kill('SIGTERM')
  const timer = setTimeout(() => server.kill('SIGKILL'), 20_000)
  await server.exited
  clearTimeout(timer)
}

async function status(): Promise<{ needsSetup: boolean }> {
  const res = await fetch(`${base}${prefix}/setup/status`)
  if (!res.ok) throw new Error(`setup/status answered ${res.status}`)
  return (await res.json()) as { needsSetup: boolean }
}

async function main(): Promise<number> {
  // Migrations on a cold Postgres can take a while on a small instance.
  const deadline = Date.now() + 240_000
  for (;;) {
    if (server.exitCode !== null) throw new Error(`Instatic exited with code ${server.exitCode} during first boot`)
    try {
      const res = await fetch(`${base}/health`)
      if (res.ok) break
    } catch {}
    if (Date.now() > deadline) throw new Error('Instatic did not answer /health on loopback within 240 s')
    await Bun.sleep(500)
  }

  if (!(await status()).needsSetup) {
    log('owner account already exists; nothing to set up')
    return 0
  }

  const email = (process.env.ADMIN_EMAIL ?? '').trim().toLowerCase()
  const password = (process.env.ADMIN_PASSWORD ?? '').trim()
  const siteName = (process.env.SITE_NAME ?? '').trim() || 'My Instatic site'
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
    throw new Error('ADMIN_EMAIL is empty or not an email address; set it on the Instatic service and redeploy')
  }
  if (password.length < 12) {
    throw new Error('ADMIN_PASSWORD must be at least 12 characters; keep the template\'s generated value')
  }

  const res = await fetch(`${base}${prefix}/setup`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ siteName, email, password, displayName: 'Owner' }),
  })
  if (res.status !== 201 && res.status !== 409) {
    throw new Error(`setup answered ${res.status}: ${(await res.text()).slice(0, 300)}`)
  }
  if ((await status()).needsSetup) throw new Error('setup still pending after creating the owner')
  log(`owner account created for ${email}`)
  return 0
}

let code = 1
try {
  code = await main()
} catch (err) {
  console.error(`[instatic-railway] ERROR: ${err instanceof Error ? err.message : String(err)}`)
  code = 1
} finally {
  await stop()
  if (lockDb) {
    try { await lockDb`select pg_advisory_unlock(${LOCK_KEY})` } catch {}
    try { await lockDb.close() } catch {}
  }
}
process.exit(code)
