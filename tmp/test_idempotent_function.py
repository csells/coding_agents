# test_idempotent_function.py
import pytest
from idempotent_function import create_resource, ensure_resource_exists, increment_resource_value, set_resource_value, Resource

def test_create_resource_not_idempotent():
    # Calling create_resource multiple times always creates new, distinct objects
    resource1 = create_resource(10)
    resource2 = create_resource(10)
    assert resource1 != resource2
    assert resource1.value == resource2.value

def test_ensure_resource_exists_idempotent():
    # First call creates the resource
    resource_initial = ensure_resource_exists(5)
    # Subsequent calls with the same value and existing resource should return the same resource
    resource_after_first_call = ensure_resource_exists(5, current_resource=resource_initial)
    resource_after_second_call = ensure_resource_exists(5, current_resource=resource_after_first_call)

    assert resource_initial is resource_after_first_call
    assert resource_after_first_call is resource_after_second_call
    assert resource_initial.value == 5

    # If the value changes, a new resource is created (not idempotent for value change)
    new_resource = ensure_resource_exists(10, current_resource=resource_initial)
    assert new_resource != resource_initial
    assert new_resource.value == 10

def test_increment_resource_value_not_idempotent():
    resource = Resource(0)
    # First call increments to 1
    increment_resource_value(resource)
    assert resource.value == 1
    # Second call increments to 2
    increment_resource_value(resource)
    assert resource.value == 2

def test_set_resource_value_idempotent():
    resource = Resource(0)
    # First call sets to 10
    set_resource_value(resource, 10)
    assert resource.value == 10
    # Second call with same value keeps it at 10
    set_resource_value(resource, 10)
    assert resource.value == 10
    # Even if we call it again, the state remains the same
    set_resource_value(resource, 10)
    assert resource.value == 10
