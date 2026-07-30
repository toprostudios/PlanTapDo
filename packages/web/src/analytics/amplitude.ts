// src/analytics/amplitude.ts
export const initAmplitude = () => {
  // Mock amplitude init
};

export const trackEvent = (event: string, props?: Record<string, any>) => {
  if (import.meta.env.DEV) {
    console.log('[Analytics]', event, props);
  }
};
