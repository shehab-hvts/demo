import { useState } from 'react'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import * as CheckboxPrimitive from '@radix-ui/react-checkbox'
import { Check, Trash2, Plus, Loader2 } from 'lucide-react'

interface Task {
  id: number
  title: string
  done: boolean
  createdAt: string
}

function cn(...classes: (string | undefined | false | null)[]) {
  return classes.filter(Boolean).join(' ')
}

function Button({
  className,
  variant = 'default',
  size = 'default',
  children,
  ...props
}: React.ButtonHTMLAttributes<HTMLButtonElement> & {
  variant?: 'default' | 'ghost'
  size?: 'default' | 'icon'
}) {
  return (
    <button
      className={cn(
        'inline-flex items-center justify-center rounded-md text-sm font-medium transition-colors',
        'focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-zinc-900',
        'disabled:pointer-events-none disabled:opacity-50',
        variant === 'default' && 'bg-zinc-900 text-white hover:bg-zinc-700',
        variant === 'ghost' && 'text-zinc-400 hover:bg-zinc-100 hover:text-zinc-900',
        size === 'default' && 'h-9 px-4',
        size === 'icon' && 'h-8 w-8',
        className
      )}
      {...props}
    >
      {children}
    </button>
  )
}

function Input({ className, ...props }: React.InputHTMLAttributes<HTMLInputElement>) {
  return (
    <input
      className={cn(
        'flex h-9 w-full rounded-md border border-zinc-200 bg-white px-3 py-1 text-sm shadow-sm',
        'placeholder:text-zinc-400',
        'focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-zinc-900',
        'disabled:cursor-not-allowed disabled:opacity-50',
        className
      )}
      {...props}
    />
  )
}

function Checkbox({
  checked,
  onCheckedChange,
}: {
  checked: boolean
  onCheckedChange: (checked: boolean) => void
}) {
  return (
    <CheckboxPrimitive.Root
      checked={checked}
      onCheckedChange={onCheckedChange}
      className={cn(
        'h-4 w-4 shrink-0 rounded-sm border border-zinc-300 shadow-sm',
        'focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-zinc-900',
        'data-[state=checked]:bg-zinc-900 data-[state=checked]:border-zinc-900 data-[state=checked]:text-white'
      )}
    >
      <CheckboxPrimitive.Indicator className="flex items-center justify-center text-current">
        <Check className="h-3 w-3" />
      </CheckboxPrimitive.Indicator>
    </CheckboxPrimitive.Root>
  )
}

async function requestJson<T>(input: RequestInfo | URL, init?: RequestInit): Promise<T> {
  const response = await fetch(input, init)
  const text = await response.text()
  const data = text ? JSON.parse(text) : null

  if (!response.ok) {
    const message = typeof data?.error === 'string'
      ? data.error
      : `Request failed with status ${response.status}`
    throw new Error(message)
  }

  return data as T
}

const api = {
  list: (): Promise<Task[]> => requestJson('/api/tasks'),
  create: (title: string): Promise<Task> =>
    requestJson('/api/tasks', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ title }),
    }),
  toggle: (id: number, done: boolean): Promise<Task> =>
    requestJson(`/api/tasks/${id}`, {
      method: 'PATCH',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ done }),
    }),
  remove: (id: number): Promise<void> =>
    requestJson(`/api/tasks/${id}`, { method: 'DELETE' }).then(() => undefined),
}

function TaskRow({
  task,
  onToggle,
  onDelete,
}: {
  task: Task
  onToggle: () => void
  onDelete: () => void
}) {
  return (
    <div className={cn(
      'group flex items-center gap-3 rounded-lg border px-4 py-3',
      task.done
        ? 'border-red-500 bg-red-100'
        : 'border-zinc-200 bg-white'
    )}>
      <Checkbox checked={task.done} onCheckedChange={onToggle} />
      <span className={cn('flex-1 text-sm', task.done && 'text-red-700 line-through font-medium')}>
        {task.title}
      </span>
      <Button
        variant="ghost"
        size="icon"
        onClick={onDelete}
        className="opacity-0 group-hover:opacity-100"
      >
        <Trash2 className="h-4 w-4" />
      </Button>
    </div>
  )
}

export default function App() {
  const [input, setInput] = useState('')
  const qc = useQueryClient()
  const invalidate = () => qc.invalidateQueries({ queryKey: ['tasks'] })

  const { data: taskList = [], isLoading, isFetching, isError, error } = useQuery({
    queryKey: ['tasks'],
    queryFn: api.list,
    retry: false,
  })

  const create = useMutation({ mutationFn: api.create, onSuccess: invalidate })
  const toggle = useMutation({
    mutationFn: ({ id, done }: { id: number; done: boolean }) => api.toggle(id, done),
    onSuccess: invalidate,
  })
  const remove = useMutation({ mutationFn: api.remove, onSuccess: invalidate })

  const handleAdd = () => {
    const title = input.trim()
    if (!title) return
    create.mutate(title)
    setInput('')
  }

  const pending = taskList.filter(t => !t.done)
  const done = taskList.filter(t => t.done)

  return (
    <div className="min-h-screen bg-red-500 flex justify-center px-4 pt-16">
      <div className="w-full max-w-md">
        <h1 className="text-2xl font-semibold tracking-tight text-zinc-900 mb-1">Tasks</h1>
        <p className="text-sm text-zinc-400 mb-6">
          {pending.length} remaining
        </p>

        <div className="flex gap-2 mb-8">
          <Input
            value={input}
            onChange={e => setInput(e.target.value)}
            onKeyDown={e => e.key === 'Enter' && handleAdd()}
            placeholder="Add a task..."
            disabled={create.isPending}
          />
          <Button onClick={handleAdd} disabled={create.isPending || !input.trim()}>
            {create.isPending ? (
              <Loader2 className="h-4 w-4 animate-spin" />
            ) : (
              <Plus className="h-4 w-4" />
            )}
          </Button>
        </div>

        {isLoading && (
          <div className="flex items-center justify-center py-12 text-zinc-400">
            <Loader2 className="h-5 w-5 animate-spin mr-2" />
            <span className="text-sm">Loading...</span>
          </div>
        )}

        {isError && (
          <p className="rounded-lg border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-700">
            {error instanceof Error ? error.message : 'Unable to load tasks.'}
          </p>
        )}

        {!isLoading && !isFetching && !isError && taskList.length === 0 && (
          <p className="text-sm text-zinc-400 text-center py-12">
            No tasks yet. Add one above.
          </p>
        )}

        {!isError && pending.length > 0 && (
          <div className="space-y-2 mb-6">
            {pending.map(task => (
              <TaskRow
                key={task.id}
                task={task}
                onToggle={() => toggle.mutate({ id: task.id, done: true })}
                onDelete={() => remove.mutate(task.id)}
              />
            ))}
          </div>
        )}

        {!isError && done.length > 0 && (
          <div>
            <p className="text-xs font-medium uppercase tracking-wider text-zinc-400 mb-2">
              Completed
            </p>
            <div className="space-y-2">
              {done.map(task => (
                <TaskRow
                  key={task.id}
                  task={task}
                  onToggle={() => toggle.mutate({ id: task.id, done: false })}
                  onDelete={() => remove.mutate(task.id)}
                />
              ))}
            </div>
          </div>
        )}
      </div>
    </div>
  )
}
