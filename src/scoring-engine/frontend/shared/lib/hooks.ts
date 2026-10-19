import { useCallback, useEffect, useRef, useState } from "react";

/** Fetch helper with reload, used by every page. */
export function useLoad<T>(loader: () => Promise<T>, deps: unknown[] = []) {
  const [data, setData] = useState<T | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const loaderRef = useRef(loader);
  loaderRef.current = loader;

  const reload = useCallback(async () => {
    try {
      const value = await loaderRef.current();
      setData(value);
      setError(null);
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    setLoading(true);
    void reload();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, deps);

  return { data, error, loading, reload, setData };
}

/**
 * Subscribes to the realtime signal stream and calls onUpdate (debounced) whenever the event changes.
 * The stream only says "something changed"; the caller refetches with its own auth.
 */
export function useLiveUpdates(url: string | null, onUpdate: () => void, debounceMs = 600) {
  const [connected, setConnected] = useState(false);
  const [lastUpdate, setLastUpdate] = useState<Date | null>(null);
  const cb = useRef(onUpdate);
  cb.current = onUpdate;

  useEffect(() => {
    if (!url) return;
    let timer: number | undefined;
    const es = new EventSource(url);
    es.addEventListener("hello", () => setConnected(true));
    es.addEventListener("update", () => {
      window.clearTimeout(timer);
      timer = window.setTimeout(() => {
        setLastUpdate(new Date());
        cb.current();
      }, debounceMs);
    });
    es.onerror = () => setConnected(false);
    es.onopen = () => setConnected(true);
    // Safety net: also refresh every 30s in case a proxy buffers the stream.
    const poll = window.setInterval(() => cb.current(), 30000);
    return () => {
      es.close();
      window.clearTimeout(timer);
      window.clearInterval(poll);
    };
  }, [url, debounceMs]);

  return { connected, lastUpdate };
}
