// src/websocket.ts
/**
 * Premium WebSocket client for real‑time Todo updates.
 * Connects to the Django Channels endpoint ``ws://localhost:8000/ws/todos/``.
 * Reconnects automatically on disconnection and provides a simple `send` method.
 * Incoming messages are logged and can be extended to dispatch actions to the
 * Zustand store.
 */

class TodoWebSocket {
  private messageHandler?: (payload: any) => void;
  private socket?: WebSocket;
  private readonly url: string;
  private reconnectDelay = 3000; // ms

  constructor(url: string) {
    this.url = url;
    this.connect();
  }

  private connect() {
    this.socket = new WebSocket(this.url);

    this.socket.onopen = () => {
      console.log('%c[WS] Connected', 'color: #7c6ff7');
    };

    this.socket.onmessage = (event: MessageEvent) => {
      try {
        const data = JSON.parse(event.data);
        console.log('%c[WS] Message', 'color: #7c6ff7', data);
        if (this.messageHandler) {
          this.messageHandler(data);
        }
      } catch (e) {
        console.log('%c[WS] Raw message', 'color: #7c6ff7', event.data);
        if (this.messageHandler) {
          this.messageHandler(null);
        }
      }
    };

    this.socket.onclose = () => {
      console.warn('%c[WS] Closed – reconnection in', 'color: orange', this.reconnectDelay, 'ms');
      setTimeout(() => this.connect(), this.reconnectDelay);
    };

    this.socket.onerror = (ev) => {
      console.error('%c[WS] Error', 'color: red', ev);
      // Force a reconnect on error
      this.socket?.close();
    };
  }

  /** Send a JSON‑serialisable payload to the server */
  public send(message: unknown) {
    if (this.socket?.readyState === WebSocket.OPEN) {
      this.socket.send(JSON.stringify(message));
    } else {
      console.warn('%c[WS] Cannot send – socket not open', 'color: orange');
    }
  }
}

// Export a singleton; the URL can be overridden via Vite env variable.
const defaultWsUrl = import.meta.env.VITE_WS_URL ?? 'ws://localhost:8000/ws/todos/';
export const wsClient = new TodoWebSocket(defaultWsUrl);

// Public API to register a message handler
export const setWsMessageHandler = (handler: (payload: any) => void) => {
  // @ts-ignore – accessing private field for registration (acceptable for internal use)
  wsClient.messageHandler = handler;
};
