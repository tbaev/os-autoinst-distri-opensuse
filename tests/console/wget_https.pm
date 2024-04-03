# SUSE's openQA tests
#
# Copyright 2016 SUSE LLC
# SPDX-License-Identifier: FSFAP

# Package: wget
# Summary: FIPS: wget
# Maintainer: QE Security <none@suse.de>
# Tags: tc#1461937


use base "consoletest";
use strict;
use warnings;
use testapi;
use utils 'zypper_call';

sub run {
    select_console "root-console";

    # Install runtime dependencies
    zypper_call("in wget");

    assert_script_run("rpm -q wget");
    assert_script_run("wget -c https://build.opensuse.org -O opensuse.html");
    assert_script_run("wget -c https://www.google.com -O google.html");
    assert_script_run("wget -c https://github.com -O github.html");
    for my $var (qw(opensuse.html google.html github.html)) {
        assert_script_run("test -f $var");
        assert_script_run("rm -f $var");
    }
}

1;
