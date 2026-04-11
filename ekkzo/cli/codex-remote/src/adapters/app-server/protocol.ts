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

export type JsonRpcNotification = {
  method: string;
  params?: unknown;
};

export type JsonRpcRequest = {
  id: string | number;
  method: string;
  params?: unknown;
};

export type JsonRpcMessage = JsonRpcSuccess | JsonRpcError | JsonRpcNotification | JsonRpcRequest;

export type NotificationHandler = (notification: JsonRpcNotification) => void;
