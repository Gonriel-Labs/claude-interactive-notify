import type { Register } from 'claude-code'

// El popup vive en scripts/notify.ps1 (dentro del plugin); este mod solo lo dispara
// a tiempo: al terminar cada respuesta y cuando Claude pide permiso o te pregunta algo.
const SCRIPT = 'scripts/notify.ps1'

export const register: Register = on => {
  // El resumen corto con el que Claude cierra el turno en la app de escritorio, si lo hay.
  let recap = ''

  // Lanza el popup sin esperarlo; si algo falla, nunca afecta a la sesion.
  const mostrar = (root: string, run: (argv: string[], init: { stdin: string; timeoutMs: number }) => Promise<unknown>, datos: object) => {
    void run(
      ['powershell.exe', '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', `${root}/${SCRIPT}`],
      { stdin: JSON.stringify(datos), timeoutMs: 90000 },
    ).catch(() => undefined)
  }

  on('turn.start', async ($, e, next) => {
    if (!e.agentId) recap = ''
    return next(e)
  })

  on('tool.call', async ($, e, next) => {
    try {
      if (!e.agentId && e.tool.endsWith('wrap_up')) {
        const args = e as unknown as { recap?: unknown; input?: { recap?: unknown } }
        const r = args.recap ?? args.input?.recap
        if (typeof r === 'string') recap = r
      }
    } catch {
      // Nunca bloquear la herramienta por esto
    }
    return next(e)
  })

  // Respuesta lista (o cortada por un error)
  on('turn.complete', async ($, e, next) => {
    const result = await next(e)

    // Solo las respuestas de la conversacion principal, no subagentes ni interrupciones.
    if (e.agentId || e.isAborted) {
      return result
    }

    const tipo = e.reason === 'error' || e.reason === 'refusal' ? 'error' : 'fin'
    mostrar($.plugin.root, (a, i) => $.process.run(a, i), {
      tipo,
      recap,
      last_assistant_message: e.answer,
      duracion_ms: e.durationMs,
    })
    return result
  })

  // Claude pide permiso o te hace una pregunta
  on('classic.Notification', async ($, e, next) => {
    const result = await next(e)
    try {
      // "Claude esta esperando tu mensaje" tras un rato sin actividad: ya lo avisa la respuesta lista
      if (e.notification_type !== 'idle_prompt') {
        mostrar($.plugin.root, (a, i) => $.process.run(a, i), {
          message: e.message,
          notification_type: e.notification_type,
        })
      }
    } catch {
      // Nunca afectar la sesion
    }
    return result
  })
}
