export const colors = {
  bg: '#071014',
  panel: '#0d1b20',
  panelRaised: '#12262d',
  text: '#e8fbf5',
  muted: '#82a9a5',
  cyan: '#47e6d2',
  lime: '#c5f36b',
  amber: '#f4b860',
  red: '#ff6f7d',
  line: '#1c3940',
}
export const styles = {
  page: {
    display: 'flex',
    flexDirection: 'column',
    flexGrow: 1,
    background: colors.bg,
    color: colors.text,
    padding: 28,
    gap: 20,
  },
  row: { display: 'flex', flexDirection: 'row', gap: 14 },
  column: { display: 'flex', flexDirection: 'column', gap: 10 },
  card: {
    background: colors.panel,
    borderRadius: 18,
    borderWidth: 1,
    borderColor: colors.line,
    padding: 18,
  },
  label: { color: colors.muted, fontSize: 12, letterSpacing: 1.2 },
  value: { color: colors.text, fontSize: 28, fontWeight: 700 },
} as const
