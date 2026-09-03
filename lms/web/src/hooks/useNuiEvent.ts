import { MutableRefObject, useEffect, useRef } from 'react';

type NuiHandlerSignature<T> = (data: T) => void;

export const useNuiEvent = <T = unknown>(
  action: string,
  handler: NuiHandlerSignature<T>
) => {
  const savedHandler: MutableRefObject<NuiHandlerSignature<T>> = useRef(handler);

  useEffect(() => {
    savedHandler.current = handler;
  }, [handler]);

  useEffect(() => {
    const listener = (event: MessageEvent) => {
      const { action: eventAction, data } = event.data;
      if (eventAction === action && savedHandler.current) {
        savedHandler.current(data as T);
      }
    };
    window.addEventListener('message', listener);
    return () => window.removeEventListener('message', listener);
  }, [action]);
};
