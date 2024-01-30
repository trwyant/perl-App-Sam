# This is not a Makefile to make anything; it is just to test the \
    Makefile syntax filter.

WHO=World

greeting:
	echo 'Hello ' \
	    '$(WHO)!'
