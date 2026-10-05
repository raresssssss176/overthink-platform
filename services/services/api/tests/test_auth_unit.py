import uuid
from app.security import hash_password,verify_password,create_access_token,decode_access_token

def test_password_roundtrip():
    value='strong-example-password-12345'
    hashed=hash_password(value)
    assert value not in hashed
    assert verify_password(value,hashed)[0] is True
    assert verify_password('not-the-password',hashed)[0] is False

def test_jwt_roundtrip():
    uid=uuid.uuid4()
    token=create_access_token(uid,1)
    payload=decode_access_token(token)
    assert payload['sub']==str(uid) and payload['cv']==1


def test_existing_bootstrap_admin_argon2_hash_is_compatible():
    from argon2 import PasswordHasher, Type
    pw = 'existing-admin-test-password'
    original_hasher = PasswordHasher(time_cost=3,memory_cost=65536,parallelism=4,hash_len=32,salt_len=16,type=Type.ID)
    original_hash = original_hasher.hash(pw)
    assert verify_password(pw, original_hash)[0] is True
