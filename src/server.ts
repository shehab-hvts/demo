import dotenv from 'dotenv'
import express from 'express'
import { drizzle } from 'drizzle-orm/node-postgres'
import { Pool } from 'pg'
import { eq } from 'drizzle-orm'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import { tasks } from './schema.js'

dotenv.config()

console.log('[Server Init] Environment:', {
  NODE_ENV: process.env.NODE_ENV,
  DATABASE_URL: process.env.DATABASE_URL ? '***' : 'NOT_SET',
  AWS_REGION: process.env.AWS_REGION
})

const pool = new Pool({ connectionString: process.env.DATABASE_URL, ssl: { rejectUnauthorized: false } })

pool.on('error', (err) => {
  console.error('[Pool Error]', err instanceof Error ? err.message : String(err))
})

pool.on('connect', () => {
  console.log('[Pool] Connected to database')
})

const db = drizzle(pool)

const app = express()
app.use(express.json())

async function ensureSchema() {
  try {
    console.log('[Schema] Initializing schema...')
    await pool.query(`
      CREATE TABLE IF NOT EXISTS tasks (
        id SERIAL PRIMARY KEY,
        title TEXT NOT NULL,
        done BOOLEAN NOT NULL DEFAULT FALSE,
        created_at TIMESTAMP NOT NULL DEFAULT NOW()
      )
    `)
    console.log('[Schema] Table created/verified')
  } catch (err) {
    console.error('[Schema] Error:', err instanceof Error ? err.message : String(err))
    throw err
  }
}

app.get('/api/tasks', async (_req, res) => {
  try {
    const result = await db.select().from(tasks).orderBy(tasks.createdAt)
    res.json(result)
  } catch (err) {
    res.status(500).json({ error: String(err) })
  }
})

app.post('/api/tasks', async (req, res) => {
  try {
    const { title } = req.body as { title?: string }
    if (!title?.trim()) { res.status(400).json({ error: 'Title required' }); return }
    const [task] = await db.insert(tasks).values({ title: title.trim() }).returning()
    res.status(201).json(task)
  } catch (err) {
    res.status(500).json({ error: String(err) })
  }
})

async function updateTask(req: express.Request, res: express.Response) {
  try {
    const id = parseInt(req.params.id)
    const { done, title } = req.body as { done?: boolean; title?: string }
    const updates: Partial<{ done: boolean; title: string }> = {}
    if (done !== undefined) updates.done = done
    if (title) updates.title = title
    const [task] = await db.update(tasks).set(updates).where(eq(tasks.id, id)).returning()
    if (!task) { res.status(404).json({ error: 'Not found' }); return }
    res.json(task)
  } catch (err) {
    res.status(500).json({ error: String(err) })
  }
}

app.put('/api/tasks/:id', updateTask)
app.patch('/api/tasks/:id', updateTask)

app.delete('/api/tasks/:id', async (req, res) => {
  try {
    const id = parseInt(req.params.id)
    const [deleted] = await db.delete(tasks).where(eq(tasks.id, id)).returning()
    if (!deleted) { res.status(404).json({ error: 'Not found' }); return }
    res.status(204).send()
  } catch (err) {
    res.status(500).json({ error: String(err) })
  }
})

if (process.env.NODE_ENV === 'production') {
  const currentDir = path.dirname(fileURLToPath(import.meta.url))
  const publicDir = path.resolve(currentDir, '../public')

  app.use(express.static(publicDir))
  app.get('*', (_req, res) => {
    res.sendFile(path.join(publicDir, 'index.html'))
  })
}

const PORT = parseInt(process.env.API_PORT || '3001')

console.log('[Startup] Starting server initialization...')
ensureSchema()
  .then(() => {
    const server = app.listen(PORT, () => {
      console.log(`[Server] API running on http://0.0.0.0:${PORT}`)
      console.log('[Server] Ready to accept requests')
    })
    server.on('error', (err) => {
      console.error('[Server] Error:', err instanceof Error ? err.message : String(err))
      process.exit(1)
    })
  })
  .catch((err) => {
    console.error('[Startup] Failed to initialize database schema')
    console.error('[Startup] Error details:', err instanceof Error ? err.message : String(err))
    console.error('[Startup] Error stack:', err instanceof Error ? err.stack : '')
    process.exit(1)
  })
