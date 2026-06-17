import { pgTable, serial, text, boolean, timestamp } from 'drizzle-orm/pg-core'

export const tasks = pgTable('tasks', {
  id: serial('id').primaryKey(),
  title: text('title').notNull(),
  done: boolean('done').notNull().default(false),
  createdAt: timestamp('created_at').notNull().defaultNow()
})

export type Task = typeof tasks.$inferSelect
