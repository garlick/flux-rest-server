#!/bin/sh

test_description='Test sharness test framework'

. $(dirname $0)/sharness.sh

test_expect_success 'sharness is working' '
	test 1 = 1
'

test_expect_success 'flux command is available' '
	flux --version
'

test_done
