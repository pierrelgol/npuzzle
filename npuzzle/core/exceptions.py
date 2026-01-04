class SolutionError(Exception):
    """Base exception for solution-related errors"""
    pass


class SolverFailedError(SolutionError):
    """Raised when the solver subprocess fails or reports failure"""
    pass


class InvalidSolutionFormat(SolutionError):
    """Raised when JSON parsing fails or solution format is invalid"""
    pass


class SubprocessError(SolutionError):
    """Raised when subprocess execution fails"""
    pass

