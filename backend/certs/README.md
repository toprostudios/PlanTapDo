# Database CA certificate

Before building a production image, place the CA certificate downloaded from
the Supabase project's Database SSL settings at:

```text
backend/certs/supabase-ca.crt
```

The certificate is public trust material rather than an application secret,
but the project-specific file is intentionally ignored so a placeholder can
never be mistaken for the certificate used by production. CI must provide the
reviewed certificate in the Docker build context. The production task template
sets `POSTGRES_SSLROOTCERT=/app/certs/supabase-ca.crt`, and Django refuses to
start when that file is missing.

