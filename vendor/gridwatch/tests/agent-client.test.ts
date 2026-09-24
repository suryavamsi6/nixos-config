import { createServer } from 'node:net'
import { mkdtemp, rm } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { afterEach, describe, expect, it } from 'vitest'
import { AgentClient } from '../src/agent-client/client'

const cleanups: Array<() => Promise<void>> = []
afterEach(async () => {
  await Promise.all(cleanups.splice(0).map((cleanup) => cleanup()))
})

describe('AgentClient', () => {
  it('exchanges one bounded newline-delimited request', async () => {
    const root = await mkdtemp(join(tmpdir(), 'gridwatch-client-'))
    const path = join(root, 'agent.sock')
    const server = createServer((socket) => {
      socket.setEncoding('utf8')
      let request = ''
      socket.on('data', (chunk) => {
        request += chunk
        if (!request.includes('\n')) return
        const parsed = JSON.parse(request) as { requestId: string }
        socket.end(
          `${JSON.stringify({
            version: 1,
            kind: 'status',
            requestId: parsed.requestId,
            payload: { agent: 'ready' },
          })}\n`,
        )
      })
    })
    await new Promise<void>((resolve, reject) => {
      server.once('error', reject)
      server.listen(path, resolve)
    })
    cleanups.push(async () => {
      await new Promise<void>((resolve) => server.close(() => resolve()))
      await rm(root, { recursive: true, force: true })
    })

    const response = await new AgentClient(path, 1_000).ping()
    expect(response.payload.agent).toBe('ready')
  })
})
