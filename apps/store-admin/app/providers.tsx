"use client";

import * as React from "react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { AuthProvider } from "@/lib/auth/auth-context";
import { StoreProvider } from "@/lib/store/store-context";
import { Toaster } from "@/components/ui/sonner";
import { RegisterSW } from "@/components/pwa/register-sw";
import { ApiError } from "@/lib/types";

export function Providers({ children }: { children: React.ReactNode }) {
  const [client] = React.useState(
    () =>
      new QueryClient({
        defaultOptions: {
          queries: {
            staleTime: 30_000,
            refetchOnWindowFocus: false,
            retry: (failureCount, error) => {
              if (error instanceof ApiError && [400, 401, 403, 404].includes(error.status)) return false;
              return failureCount < 2;
            },
          },
        },
      })
  );

  return (
    <QueryClientProvider client={client}>
      <AuthProvider>
        <StoreProvider>{children}</StoreProvider>
      </AuthProvider>
      <Toaster />
      <RegisterSW />
    </QueryClientProvider>
  );
}
