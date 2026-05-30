import type { AttendanceState, AuthResponse, StateResponse } from "./types";

const JWT_STORAGE = "WFH_WEB_JWT";
const USER_STORAGE = "WFH_WEB_USER";

export function apiBase(): string {
  return String(window.WFH_API?.apiBase ?? "").trim().replace(/\/$/, "");
}

export function apiUrl(path: string): string {
  const p = path.startsWith("/") ? path : `/${path}`;
  return `${apiBase()}${p}`;
}

export function loadToken(): string | null {
  return sessionStorage.getItem(JWT_STORAGE);
}

export function saveSession(token: string, user: unknown): void {
  sessionStorage.setItem(JWT_STORAGE, token);
  sessionStorage.setItem(USER_STORAGE, JSON.stringify(user));
}

export function loadUser<T>(): T | null {
  const raw = sessionStorage.getItem(USER_STORAGE);
  if (!raw) return null;
  try {
    return JSON.parse(raw) as T;
  } catch {
    return null;
  }
}

export function clearSession(): void {
  sessionStorage.removeItem(JWT_STORAGE);
  sessionStorage.removeItem(USER_STORAGE);
}

type ApiRequestInit = Omit<RequestInit, "body"> & { body?: unknown };

async function request<T>(path: string, init: ApiRequestInit = {}, skipAuth = false): Promise<T> {
  const headers = new Headers(init.headers);
  let body = init.body;
  if (body && typeof body === "object" && !(body instanceof FormData)) {
    headers.set("Content-Type", "application/json");
    body = JSON.stringify(body);
  }
  const token = loadToken();
  if (token && !skipAuth) headers.set("Authorization", `Bearer ${token}`);

  const controller = new AbortController();
  const timeout = window.setTimeout(() => controller.abort(), 28000);
  try {
    const response = await fetch(apiUrl(path), { ...init, headers, body: body as BodyInit | null | undefined, signal: controller.signal });
    const text = await response.text();
    let data: unknown = null;
    try {
      data = text ? JSON.parse(text) : null;
    } catch {
      data = { error: text || "Invalid response" };
    }
    if (!response.ok) {
      const error = data && typeof data === "object" && "error" in data ? String(data.error) : "Request failed";
      throw new Error(error);
    }
    return data as T;
  } catch (error) {
    if (error instanceof DOMException && error.name === "AbortError") {
      throw new Error("Request timed out. Check your connection and try again.");
    }
    throw error;
  } finally {
    window.clearTimeout(timeout);
  }
}

export const api = {
  health: () => request<{ ok: boolean }>("/api/health", {}, true),
  register: (email: string, password: string) =>
    request<{ ok: boolean; message?: string }>("/api/auth/register", { method: "POST", body: { email, password } }, true),
  verifyEmail: (token: string) =>
    request<{ ok: boolean; message?: string }>("/api/auth/verify-email", { method: "POST", body: { token } }, true),
  signIn: (email: string, password: string) =>
    request<AuthResponse>("/api/auth/login", { method: "POST", body: { email, password } }, true),
  forgotPassword: (email: string) =>
    request<{ ok: boolean; message?: string }>("/api/auth/forgot-password", { method: "POST", body: { email } }, true),
  google: (credential: string) =>
    request<AuthResponse>("/api/auth/google", { method: "POST", body: { credential } }, true),
  apple: (idToken: string) =>
    request<AuthResponse>("/api/auth/apple", { method: "POST", body: { idToken } }, true),
  loadState: () => request<StateResponse>("/api/state"),
  saveState: (payload: AttendanceState) => request<{ ok: boolean }>("/api/state", { method: "PUT", body: { payload } }),
};
