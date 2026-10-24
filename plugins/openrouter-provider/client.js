window.__ModuleLoader__.load({
  id: '@local/openrouter-provider',
  factory(require) {
    const React = require('react')
    const h = React.createElement
    const PATH = 'api/openrouter-provider'
    const NS = 'openrouter-provider'

    const CSS = [
      '.orp{position:relative;display:inline-flex;align-items:center}',
      '.orp-btn{box-sizing:border-box;height:28px;max-width:168px;border:0;border-radius:8px;padding:0 8px;display:inline-flex;align-items:center;gap:6px;background:transparent;color:var(--dsw-alias-label-secondary);font:inherit;font-size:12px;line-height:16px;cursor:pointer}',
      '.orp-btn:hover,.orp-btn[aria-expanded="true"]{background:var(--dsw-alias-bg-layer-2);color:var(--dsw-alias-label-primary)}',
      '.orp-btn:disabled{cursor:default;opacity:.55}',
      '.orp-btn:focus-visible,.orp-mode:focus-visible,.orp-row:focus-visible{outline:1px solid var(--dsw-alias-brand-primary);outline-offset:1px}',
      '.orp-label{overflow:hidden;text-overflow:ellipsis;white-space:nowrap}',
      '.orp-pop{position:absolute;right:0;bottom:calc(100% + 6px);z-index:30;width:280px;max-height:320px;overflow:auto;box-sizing:border-box;border:.5px solid var(--dsw-alias-border-l1);border-radius:12px;background:var(--dsw-alias-bg-overlay);color:var(--dsw-alias-label-primary);padding:8px;box-shadow:0 8px 24px color-mix(in srgb, var(--dsw-alias-label-primary) 12%, transparent)}',
      '.orp-note,.orp-empty{margin:0;color:var(--dsw-alias-label-secondary);font-size:12px;line-height:18px}',
      '.orp-error{margin:6px 0 0;color:var(--dsw-alias-state-error-primary);font-size:12px;line-height:18px}',
      '.orp-modes{display:flex;gap:4px;margin:8px 0}',
      '.orp-mode{border:0;border-radius:999px;padding:4px 8px;background:transparent;color:var(--dsw-alias-label-secondary);font:inherit;font-size:11px;line-height:16px;cursor:pointer}',
      '.orp-mode[aria-pressed="true"]{background:var(--dsw-alias-bg-layer-2);color:var(--dsw-alias-label-primary)}',
      '.orp-list{display:flex;flex-direction:column;gap:2px;margin:0;padding:0;list-style:none}',
      '.orp-row{width:100%;border:0;border-radius:8px;padding:6px 8px;display:flex;flex-direction:column;align-items:flex-start;gap:1px;background:transparent;color:inherit;font:inherit;text-align:left;cursor:pointer}',
      '.orp-row:hover,.orp-row[aria-current="true"]{background:var(--dsw-alias-bg-layer-2)}',
      '.orp-name{font-size:13px;line-height:18px}',
      '.orp-meta{color:var(--dsw-alias-label-secondary);font-size:11px;line-height:16px}',
    ].join('')

    const EN = {
      button: 'Provider',
      default: 'OpenRouter chooses',
      only: 'Only',
      order: 'Try first',
      note: 'Chat completions only. The choice lasts until restart.',
      empty: 'No upstream providers reported.',
      failed: 'Could not load providers.',
    }
    const ZH = {
      button: '提供方',
      default: '由 OpenRouter 选择',
      only: '仅此',
      order: '优先',
      note: '仅用于聊天补全。选择会保留到重启。',
      empty: '没有返回上游提供方。',
      failed: '无法加载提供方。',
    }

    function selectedModel(snapshot) {
      if (!snapshot || typeof snapshot !== 'object') return ''
      const next = snapshot.next || snapshot.lastUsed
      if (!next || next.provider !== 'openrouter' || typeof next.model !== 'string') return ''
      return next.model
    }

    function price(endpoint) {
      const parts = []
      if (endpoint.prompt) parts.push(`$${Number(endpoint.prompt) * 1e6}/M in`)
      if (endpoint.completion) parts.push(`$${Number(endpoint.completion) * 1e6}/M out`)
      return parts.join(' · ')
    }

    async function callRoute(body, signal) {
      const response = await fetch(PATH, {
        method: 'POST',
        cache: 'no-store',
        credentials: 'same-origin',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify(body),
        signal,
      })
      const payload = await response.json().catch(() => ({}))
      if (!response.ok || payload.ok === false) throw new Error(payload.error || `HTTP ${response.status}`)
      return payload
    }

    function ProviderButton({ useProjection, t }) {
      const model = selectedModel(useProjection('modelSelection'))
      const [open, setOpen] = React.useState(false)
      const [mode, setMode] = React.useState('order')
      const [choice, setChoice] = React.useState({ mode: 'default', slug: '' })
      const [endpoints, setEndpoints] = React.useState([])
      const [error, setError] = React.useState('')
      const [busy, setBusy] = React.useState(false)
      const root = React.useRef(null)

      React.useEffect(() => {
        if (!open) return undefined
        const close = (event) => {
          if (root.current && !root.current.contains(event.target)) setOpen(false)
        }
        const onKey = (event) => {
          if (event.key === 'Escape') setOpen(false)
        }
        document.addEventListener('pointerdown', close)
        document.addEventListener('keydown', onKey)
        return () => {
          document.removeEventListener('pointerdown', close)
          document.removeEventListener('keydown', onKey)
        }
      }, [open])

      React.useEffect(() => {
        if (!model) return undefined
        const controller = new AbortController()
        setBusy(true)
        setError('')
        callRoute({ action: 'list', model }, controller.signal).then((payload) => {
          setChoice(payload.choice || { mode: 'default', slug: '' })
          setEndpoints(Array.isArray(payload.endpoints) ? payload.endpoints : [])
          setBusy(false)
        }).catch((reason) => {
          if (controller.signal.aborted) return
          setError(reason instanceof Error ? reason.message : t('failed'))
          setBusy(false)
        })
        return () => controller.abort()
      }, [model])

      if (!model) return null

      const label = choice.mode === 'default' ? t('default') : choice.slug
      const choose = (nextMode, slug) => {
        setBusy(true)
        setError('')
        callRoute({ action: 'set', model, mode: nextMode, slug }).then((payload) => {
          setChoice(payload.choice || { mode: 'default', slug: '' })
          setBusy(false)
          if (nextMode === 'default') setOpen(false)
        }).catch((reason) => {
          setError(reason instanceof Error ? reason.message : t('failed'))
          setBusy(false)
        })
      }

      return h('div', { className: 'orp', ref: root },
        h('style', null, CSS),
        h('button', {
          type: 'button',
          className: 'orp-btn',
          title: t('button'),
          'aria-label': t('button'),
          'aria-expanded': open,
          'aria-haspopup': 'dialog',
          disabled: busy && !open,
          onClick: () => setOpen((value) => !value),
        }, h('span', { className: 'orp-label' }, label)),
        open ? h('div', { className: 'orp-pop', role: 'dialog', 'aria-label': t('button') },
          h('p', { className: 'orp-note' }, t('note')),
          h('div', { className: 'orp-modes', role: 'group' },
            ['order', 'only'].map((item) => h('button', {
              key: item,
              type: 'button',
              className: 'orp-mode',
              'aria-pressed': mode === item,
              onClick: () => {
                setMode(item)
                if (choice.slug) choose(item, choice.slug)
              },
            }, t(item)))),
          h('button', {
            type: 'button',
            className: 'orp-row',
            'aria-current': choice.mode === 'default',
            disabled: busy,
            onClick: () => choose('default', ''),
          }, h('span', { className: 'orp-name' }, t('default'))),
          endpoints.length === 0
            ? h('p', { className: 'orp-empty' }, busy ? '…' : t('empty'))
            : h('ul', { className: 'orp-list' }, endpoints.map((endpoint) => h('li', { key: endpoint.tag },
              h('button', {
                type: 'button',
                className: 'orp-row',
                'aria-current': choice.slug === endpoint.tag,
                disabled: busy,
                onClick: () => choose(mode, endpoint.tag),
              },
                h('span', { className: 'orp-name' }, endpoint.name),
                h('span', { className: 'orp-meta' }, [endpoint.tag, price(endpoint)].filter(Boolean).join(' · ')))))),
          error ? h('p', { className: 'orp-error', role: 'alert' }, error) : null) : null)
    }

    return {
      inject: ['slots', 'locale'],
      apply(ctx) {
        ctx.effect(() => ctx.locale.register(NS, 'en', EN), 'openrouter-provider: en')
        ctx.effect(() => ctx.locale.register(NS, 'zh', ZH), 'openrouter-provider: zh')
        const t = ctx.locale.bind(NS)
        ctx.slots.inject('conversation.input.right', () => ctx.slots.register({
          name: 'conversation.input.right',
          id: 'openrouter-provider',
          order: 20,
          label: () => t('button'),
        }, (props) => h(ProviderButton, { ...props, t })))
      },
    }
  },
})
