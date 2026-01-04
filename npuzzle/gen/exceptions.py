class GeneratorError(Exception):
    pass


class InvalidSize(GeneratorError):
    pass


class ConflictingOptions(GeneratorError):
    pass


class MissingArgument(GeneratorError):
    pass


class InvalidNumber(GeneratorError):
    pass
