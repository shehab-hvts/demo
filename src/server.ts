import express from 'express'
import { drizzle } from 'drizzle-orm/node-postgres'
import { Pool } from 'pg'
import { eq } from 'drizzle-orm'
import { tasks } from './schema.js'

const pool = new Pool({ connectionString: process.env.DATABASE_URL })
const db = drizzle(pool)

const app = express()
app.use(express.json())

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

app.patch('/api/tasks/:id', async (req, res) => {
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
})

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

const PORT = parseInt(process.env.API_PORT || '3001')
app.listen(PORT, () => console.log(`API on :${PORT}`))
