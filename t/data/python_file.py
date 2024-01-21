#!/usr/bin/env python
# This is a single-line comment

"""
This is a multi-line comment.
"""
import sys

def who():
    """ This function determines who we are greeting """
    if len( sys.argv ) > 1:
        return sys.argv[1] + "!"
    return "World!"

print "Hello", who()

# ex: set filetype=python textwidth=72 autoindent :
