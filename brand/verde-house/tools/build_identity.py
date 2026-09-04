#!/usr/bin/env python3
"""Rebuild every Verde House mark from geometry. Run from anywhere."""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import identity

if __name__ == "__main__":
    for f in identity.emit():
        print(f)
