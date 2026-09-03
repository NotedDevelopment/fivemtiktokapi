import { isEnvBrowser } from './misc';

export function debugData<P>(
  events: Array<{ action: string; data: P }>,
  timer = 1000
): void {
  if (!isEnvBrowser()) return;
  for (const event of events) {
    setTimeout(() => {
      window.dispatchEvent(
        new MessageEvent('message', { data: { action: event.action, data: event.data } })
      );
    }, timer);
  }
}
