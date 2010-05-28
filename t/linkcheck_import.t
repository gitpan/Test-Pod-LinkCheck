#!/usr/bin/perl
# 
# This file is part of Test-Pod-LinkCheck
# 
# This software is copyright (c) 2010 by Apocalypse.
# 
# This is free software; you can redistribute it and/or modify it under
# the same terms as the Perl 5 programming language system itself.
# 
use strict; use warnings;

use Test::Pod::LinkCheck qw( all_pod_ok );

# run the test!
all_pod_ok();