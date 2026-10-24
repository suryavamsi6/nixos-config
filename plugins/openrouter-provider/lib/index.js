/**
 * Choose which OpenRouter upstream serves a model.
 *
 * Harness withholds pi-ai's `compat.openRouterRouting`, and loop requests are
 * frozen, so this cannot be a model-config or request rewrite. Completions
 * clients are built per call and read `globalThis.fetch`, which is where the
 * `provider` object is merged into an OpenRouter chat-completions body.
 *
 * The composer reaches the same operation through an authenticated `/api`
 * route. A process restart clears the choice; it is not written to settings.
 *
 * @module @local/openrouter-provider
 */

const ROUTE = '/api/openrouter-provider'
const ENDPOINTS = 'https://openrouter.ai/api/v1/models'
const KEY_REF = 'OPENROUTER_API_KEY'
const MARK = Symbol.for('@local/openrouter-provider.fetch')
const BASE = Symbol.for('@local/openrouter-provider.fetch-base')
const MODES = ['default', 'only', 'order']
const MODEL_ID = /^[A-Za-z0-9][A-Za-z0-9._~:-]{0,127}\/[A-Za-z0-9][A-Za-z0-9._~:-]{0,127}$/
const SLUG = /^[A-Za-z0-9][A-Za-z0-9._~:-]{0,63}(?:\/[A-Za-z0-9][A-Za-z0-9._~:-]{0,63})?$/

/** @type {Map<string, { mode: 'only' | 'order', slug: string }>} */
const choices = new Map()

/**
 * @param {unknown} value
 * @returns {value is Record<string, unknown>}
 */
function record(value) {
  return typeof value === 'object' && value !== null && !Array.isArray(value)
}

/**
 * @param {string} model
 * @returns {{ author: string, slug: string } | undefined}
 */
function splitModel(model) {
  if (!MODEL_ID.test(model)) return undefined
  const slash = model.indexOf('/')
  return { author: model.slice(0, slash), slug: model.slice(slash + 1) }
}

/**
 * @param {unknown} raw
 * @returns {{ mode: 'only' | 'order', slug: string } | undefined}
 */
function parseChoice(raw) {
  if (!record(raw)) return undefined
  if (raw.mode === 'default' || raw.slug === '') return undefined
  if (raw.mode !== 'only' && raw.mode !== 'order') return undefined
  if (typeof raw.slug !== 'string' || !SLUG.test(raw.slug)) return undefined
  return { mode: raw.mode, slug: raw.slug }
}

/**
 * @param {string} model
 * @returns {{ mode: 'default' | 'only' | 'order', slug: string }}
 */
function readChoice(model) {
  const saved = choices.get(model)
  return saved ? { mode: saved.mode, slug: saved.slug } : { mode: 'default', slug: '' }
}

/**
 * The OpenRouter `provider` object for one saved choice.
 * `only` allows that slug alone; `order` tries it first and may fall back.
 * @param {{ mode: 'only' | 'order', slug: string } | undefined} choice
 * @returns {Record<string, unknown> | undefined}
 */
function routingOf(choice) {
  if (!choice) return undefined
  if (choice.mode === 'only') return { only: [choice.slug], allow_fallbacks: false }
  return { order: [choice.slug], allow_fallbacks: true }
}

/**
 * @param {number} status
 * @param {Record<string, unknown>} body
 * @returns {Response}
 */
function json(status, body) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      'content-type': 'application/json',
      'cache-control': 'no-store',
    },
  })
}

/**
 * @param {string} value
 * @returns {URL | undefined}
 */
function parseUrl(value) {
  try {
    return new URL(value)
  } catch {
    return undefined
  }
}

/**
 * @param {string} hostname
 * @returns {boolean}
 */
function openRouterHost(hostname) {
  return hostname === 'openrouter.ai' || hostname.endsWith('.openrouter.ai')
}

/**
 * @param {RequestInfo | URL} input
 * @returns {URL | undefined}
 */
function requestUrl(input) {
  if (typeof input === 'string') return parseUrl(input)
  if (input instanceof URL) return input
  if (typeof Request !== 'undefined' && input instanceof Request) return parseUrl(input.url)
  return undefined
}

/**
 * @param {RequestInfo | URL} input
 * @param {RequestInit | undefined} init
 * @returns {{ url: URL, method: string, body: BodyInit | null | undefined } | undefined}
 */
function completionRequest(input, init) {
  const url = requestUrl(input)
  if (!url || !openRouterHost(url.hostname)) return undefined
  if (!url.pathname.endsWith('/chat/completions')) return undefined
  const method = (init?.method || (typeof Request !== 'undefined' && input instanceof Request ? input.method : 'GET')).toUpperCase()
  if (method !== 'POST') return undefined
  const body = init && 'body' in init ? init.body : undefined
  if (typeof body !== 'string') return undefined
  return { url, method, body }
}

/**
 * Merge a saved choice into one OpenRouter chat-completions body.
 * A body that already names `provider`, or a model with no choice, passes through.
 * @param {string} body
 * @returns {string}
 */
function rewriteBody(body) {
  let parsed
  try {
    parsed = JSON.parse(body)
  } catch {
    return body
  }
  if (!record(parsed) || typeof parsed.model !== 'string' || 'provider' in parsed) return body
  const routing = routingOf(choices.get(parsed.model))
  if (!routing) return body
  return JSON.stringify({ ...parsed, provider: routing })
}

/**
 * @param {import('@deepseek-ai/cordis').Context} ctx
 * @returns {() => void}
 */
function installFetch(ctx) {
  const current = globalThis.fetch
  if (typeof current !== 'function') return () => {}
  const base = current[MARK] === true && typeof current[BASE] === 'function' ? current[BASE] : current
  const wrapped = async function openRouterFetch(input, init) {
    const target = completionRequest(input, init)
    if (!target) return base(input, init)
    return base(input, { ...init, body: rewriteBody(target.body) })
  }
  Object.defineProperty(wrapped, MARK, { value: true })
  Object.defineProperty(wrapped, BASE, { value: base })
  globalThis.fetch = wrapped
  return ctx.effect(() => () => {
    if (globalThis.fetch?.[MARK] === true) globalThis.fetch = base
  }, 'openrouter-provider: restore fetch')
}

/**
 * @param {import('@deepseek-ai/cordis').Context} ctx
 * @returns {Promise<string | undefined>}
 */
async function resolveKey(ctx) {
  const credentials = ctx.get('credentials')
  if (credentials && typeof credentials.resolve === 'function') {
    try {
      const resolved = await credentials.resolve(KEY_REF)
      if (resolved && typeof resolved.value === 'string' && resolved.value) return resolved.value
    } catch {
      // A missing store still leaves the public endpoint list usable.
    }
  }
  const fromEnv = process.env[KEY_REF]
  return fromEnv || undefined
}

/**
 * @param {unknown} raw
 * @returns {{ name: string, tag: string, context: number, prompt: string, completion: string }[]}
 */
function endpointsOf(raw) {
  const rows = record(raw) && record(raw.data) && Array.isArray(raw.data.endpoints) ? raw.data.endpoints : []
  const seen = new Set()
  const endpoints = []
  for (const row of rows) {
    if (!record(row) || typeof row.tag !== 'string' || !SLUG.test(row.tag) || seen.has(row.tag)) continue
    seen.add(row.tag)
    const pricing = record(row.pricing) ? row.pricing : {}
    endpoints.push({
      name: typeof row.provider_name === 'string' && row.provider_name ? row.provider_name : row.tag,
      tag: row.tag,
      context: typeof row.context_length === 'number' ? row.context_length : 0,
      prompt: typeof pricing.prompt === 'string' ? pricing.prompt : '',
      completion: typeof pricing.completion === 'string' ? pricing.completion : '',
    })
  }
  return endpoints
}

/**
 * @param {import('@deepseek-ai/cordis').Context} ctx
 * @param {string} model
 * @param {AbortSignal} signal
 * @returns {Promise<{ name: string, tag: string, context: number, prompt: string, completion: string }[]>}
 */
async function listEndpoints(ctx, model, signal) {
  const parts = splitModel(model)
  if (!parts) throw new Error('OpenRouter model id must be author/slug.')
  const key = await resolveKey(ctx)
  const response = await fetch(`${ENDPOINTS}/${encodeURIComponent(parts.author)}/${encodeURIComponent(parts.slug)}/endpoints`, {
    headers: {
      accept: 'application/json',
      ...key ? { authorization: `Bearer ${key}` } : {},
    },
    signal,
  })
  if (!response.ok) throw new Error(`OpenRouter endpoint list returned HTTP ${response.status}.`)
  return endpointsOf(await response.json())
}

/**
 * Shared list/set operation. `list` returns the saved choice and live upstreams.
 * `set` stores one choice for later chat-completions requests.
 * @param {import('@deepseek-ai/cordis').Context} ctx
 * @param {unknown} args
 * @param {AbortSignal} [signal]
 * @returns {Promise<Record<string, unknown>>}
 */
async function selectProvider(ctx, args, signal) {
  if (!record(args) || typeof args.model !== 'string' || !MODEL_ID.test(args.model)) {
    return { ok: false, error: 'OpenRouter model id must be author/slug.' }
  }
  if (args.action === 'list') {
    const endpoints = await listEndpoints(ctx, args.model, signal ?? AbortSignal.timeout(15000))
    return { ok: true, model: args.model, choice: readChoice(args.model), endpoints }
  }
  if (args.action !== 'set') return { ok: false, error: 'Action must be list or set.' }
  if (typeof args.mode !== 'string' || !MODES.includes(args.mode)) {
    return { ok: false, error: 'Mode must be default, only, or order.' }
  }
  if (args.mode === 'default') {
    choices.delete(args.model)
    return { ok: true, model: args.model, choice: readChoice(args.model) }
  }
  const choice = parseChoice({ mode: args.mode, slug: args.slug })
  if (!choice) return { ok: false, error: 'Provider slug must be an OpenRouter endpoint tag.' }
  choices.set(args.model, choice)
  return { ok: true, model: args.model, choice: readChoice(args.model) }
}

/**
 * @param {Request} request
 * @param {import('@deepseek-ai/cordis').Context} ctx
 * @returns {Promise<Response>}
 */
async function handleRoute(request, ctx) {
  let body
  try {
    body = await request.json()
  } catch {
    return json(400, { ok: false, error: 'Expected a JSON body.' })
  }
  try {
    return json(200, await selectProvider(ctx, body, request.signal))
  } catch (error) {
    const message = error instanceof Error ? error.message : 'OpenRouter provider selection failed.'
    return json(502, { ok: false, error: message })
  }
}

/**
 * @param {import('@deepseek-ai/cordis').Context} ctx
 * @returns {() => void}
 */
function registerTool(ctx) {
  return ctx.tools.register({
    name: 'openrouter_provider',
    description: 'Choose which OpenRouter upstream provider serves one OpenRouter chat-completions model. Use list to see endpoint tags, then set mode to order (try that provider first), only (allow that provider alone), or default (let OpenRouter choose). This does not route Anthropic-format OpenRouter models.',
    parameters: {
      type: 'object',
      additionalProperties: false,
      required: ['action', 'model'],
      properties: {
        action: { type: 'string', enum: ['list', 'set'], description: 'list returns the saved choice and live endpoint tags. set stores a choice.' },
        model: { type: 'string', description: 'OpenRouter model id, author/slug.' },
        mode: { type: 'string', enum: MODES, description: 'Required for set. default clears the choice.' },
        slug: { type: 'string', description: 'Endpoint tag from list. Required for only and order, for example azure/global.' },
      },
    },
    output: {
      schema: { type: 'object' },
      render(_args, value) {
        if (!record(value) || value.ok === false) return [{ type: 'text', text: 'OpenRouter provider selection failed.' }]
        const choice = record(value.choice) ? value.choice : {}
        const label = choice.mode === 'default' || !choice.slug ? 'OpenRouter chooses' : `${choice.mode}: ${choice.slug}`
        return [{ type: 'text', text: `${value.model}: ${label}` }]
      },
    },
    execute(args) {
      return selectProvider(ctx, args)
    },
    presentCall(args) {
      const model = record(args) && typeof args.model === 'string' ? args.model : ''
      return { card: 'generic', title: 'OpenRouter provider', kind: 'other', rawInput: model || undefined }
    },
  })
}

/** @type {string[]} */
export const inject = ['connection', 'tools']

/**
 * @param {import('@deepseek-ai/cordis').Context} ctx
 */
export function apply(ctx) {
  installFetch(ctx)
  ctx.effect(() => registerTool(ctx), 'openrouter-provider: tool')
  ctx.effect(() => ctx.connection.fetch.register({
    path: ROUTE,
    methods: ['POST'],
    requestBody: 'buffered',
    fetch: (request) => handleRoute(request, ctx),
  }), 'openrouter-provider: picker route')
}
