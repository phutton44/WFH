/// <reference types="vite/client" />

interface Window {
  WFH_API?: {
    apiBase?: string;
    googleClientId?: string;
    appleClientId?: string;
    appleRedirectURI?: string;
  };
  AppleID?: {
    auth?: {
      init: (options: unknown) => void;
      signIn: () => Promise<{
        authorization?: {
          id_token?: string;
          code?: string;
          state?: string;
        };
      }>;
    };
  };
  google?: {
    accounts?: {
      id?: {
        initialize: (options: unknown) => void;
        renderButton: (element: HTMLElement, options: unknown) => void;
        prompt: () => void;
      };
    };
  };
}
