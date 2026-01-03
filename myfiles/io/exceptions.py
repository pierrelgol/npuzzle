class IOError(Exception):
    pass


class InvalidCharacterError(IOError):
    pass


class InvalidSizeError(IOError):
    pass


class MissingSizeError(IOError):
    pass


class InvalidDimensions(IOError):
    pass
