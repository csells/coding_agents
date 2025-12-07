# idempotent_function.py

class Resource:
    def __init__(self, value):
        self.value = value

    def __eq__(self, other):
        if not isinstance(other, Resource):
            return NotImplemented
        return self.value == other.value

def create_resource(initial_value):
    """
    Creates a new resource with the given initial_value.
    This function is NOT idempotent by itself as it creates a new object every time.
    """
    return Resource(initial_value)

def ensure_resource_exists(initial_value, current_resource=None):
    """
    Ensures a resource with the given initial_value exists.
    If current_resource is provided and its value matches initial_value, it's considered idempotent.
    Otherwise, a new resource is created.
    """
    if current_resource and current_resource.value == initial_value:
        return current_resource
    return Resource(initial_value)

def increment_resource_value(resource):
    """
    Increments the value of a resource.
    This function is NOT idempotent.
    """
    resource.value += 1
    return resource

def set_resource_value(resource, new_value):
    """
    Sets the value of a resource to a specific new_value.
    This function IS idempotent. Repeated calls with the same new_value have the same effect.
    """
    resource.value = new_value
    return resource
