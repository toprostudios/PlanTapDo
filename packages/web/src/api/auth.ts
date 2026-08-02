// src/api/auth.ts
import api from './client';

export interface RegisterPayload {
  username: string;
  email: string;
  password?: string;
  first_name?: string;
  last_name?: string;
}

export interface RegisterResponse {
  id: string;
  username: string;
  email: string;
  tokens: {
    access: string;
    refresh: string;
  };
}

export interface UserProfile {
  id: string;
  username: string;
  email: string;
  first_name: string;
  last_name: string;
}

export const registerAccount = async (payload: RegisterPayload): Promise<RegisterResponse> => {
  const data = await api.post<RegisterResponse>('/auth/register/', {
    ...payload,
    password: payload.password || 'password123',
  });
  if (data.tokens?.access) {
    localStorage.setItem('plantapdo_jwt', data.tokens.access);
  }
  return data;
};

export const getProfile = async (): Promise<UserProfile> => {
  return api.get<UserProfile>('/auth/me/');
};

export const loginAccount = async (username: string, password: string): Promise<{ access: string; refresh: string }> => {
  const tokens = await api.post<{ access: string; refresh: string }>('/auth/token/', { username, password });
  if (tokens.access) {
    localStorage.setItem('plantapdo_jwt', tokens.access);
  }
  return tokens;
};
