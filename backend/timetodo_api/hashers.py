"""Password hashers with an explicit, reviewable security baseline."""

from django.contrib.auth.hashers import Argon2PasswordHasher


class OWASPArgon2PasswordHasher(Argon2PasswordHasher):
    """Argon2id using the OWASP minimum profile for password storage.

    Django and argon2-cffi generate a unique random salt for every password.
    These values are intentionally explicit so dependency defaults cannot
    silently weaken the deployment's password-storage policy.
    """

    time_cost = 2
    memory_cost = 19 * 1024
    parallelism = 1

