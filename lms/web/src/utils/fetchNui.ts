import { isEnvBrowser } from './misc';

export async function fetchNui<T = unknown>(
  eventName: string,
  data: unknown = {},
  mockData?: T
): Promise<T> {
  if (isEnvBrowser() && mockData !== undefined) return mockData;

  const resourceName = (window as any).GetParentResourceName
    ? (window as any).GetParentResourceName()
    : 'lms';

  const resp = await fetch(`https://${resourceName}/${eventName}`, {
    method: 'post',
    headers: { 'Content-Type': 'application/json; charset=UTF-8' },
    body: JSON.stringify(data),
  });

  return await resp.json();
}
