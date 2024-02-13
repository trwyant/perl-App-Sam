#!/usr/bin/env swift

/* This is a block comment.
 * /* Note that they nest, */
 * so this is still a comment.
 */

/*:
 * This is a Swift implementation of 'Hello world', which accepts an
 * optional command line parameter specifying who to greet.
 *
 * The colon on the first line makes this documentation.
 */

// Note that the following makes 'name' a manifest constant.
let name = CommandLine.argc > 1 ? CommandLine.arguments[ 1 ] : "world"

print( "Hello " + name + "!" )
