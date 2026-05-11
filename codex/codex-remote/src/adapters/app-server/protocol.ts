import type {
  ClientNotification,
  ClientRequest,
  ServerNotification,
  ServerRequest,
} from "./generated/index.js";

export type JsonRpcSuccess = {
  id: number | string;
  result: unknown;
};

export type JsonRpcError = {
  id: number | string;
  error: {
    code: number;
    message: string;
    data?: unknown;
  };
};

export type JsonRpcNotification = ServerNotification | { method: string; params?: unknown };
export type JsonRpcRequest = ServerRequest | { id: string | number; method: string; params?: unknown };
export type JsonRpcClientRequest = ClientRequest;
export type JsonRpcClientNotification = ClientNotification;

export type JsonRpcMessage = JsonRpcSuccess | JsonRpcError | JsonRpcNotification | JsonRpcRequest;

export type NotificationHandler = (notification: JsonRpcNotification) => void;
