.PHONY: all clean test run re

# Default target
all:
	zig build

# Clean build artifacts
clean:
	rm -rf zig-out zig-cache .zig-cache
	rm -f test_puzzle.txt test_puzzle2.txt test_unsolvable.txt

# Run tests
test:
	zig build test

# Run the program with a default puzzle
run:
	@if [ ! -f test_puzzle.txt ]; then \
		echo "Generating test puzzle..."; \
		python3 src/npuzzle-gen.py 3 -s -i 50 > test_puzzle.txt; \
	fi
	zig build run -- test_puzzle.txt

# Rebuild everything
re: clean all

# Help message
help:
	@echo "N-Puzzle Solver Makefile"
	@echo ""
	@echo "Targets:"
	@echo "  all     - Build the npuzzle binary (default)"
	@echo "  clean   - Remove build artifacts and test files"
	@echo "  test    - Run all unit tests"
	@echo "  run     - Build and run with a generated test puzzle"
	@echo "  re      - Clean and rebuild"
	@echo "  help    - Show this help message"
	@echo ""
	@echo "Usage examples:"
	@echo "  make              # Build the project"
	@echo "  make test         # Run tests"
	@echo "  make run          # Generate puzzle and solve it"
	@echo "  ./zig-out/bin/npuzzle --help  # See CLI options"
