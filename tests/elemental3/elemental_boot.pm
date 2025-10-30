# Copyright 2025 SUSE LLC
# SPDX-License-Identifier: FSFAP

# Summary: Boot Elemental3 OS image.
# Maintainer: unified-core@suse.com, ldevulder@suse.com

use base qw(opensusebasetest);
use testapi;
use lockapi;
use mm_network qw(configure_hostname setup_static_mm_network);
use serial_terminal qw(select_serial_terminal);

sub run {
    my ($self) = @_;

    # Set default root password
    $testapi::password = get_required_var('TEST_PASSWORD');

    # For UC OS image boot
    if (check_var('IMAGE_TYPE', 'disk')) {
        # Wait for GRUB and select default entry
        $self->wait_grub(bootloader_time => 300);
        send_key('ret', wait_screen_change => 1);
        wait_still_screen(timeout => 120);
        save_screenshot();
    }

    # No GUI, easier and quicker to use the serial console
    select_serial_terminal();

    # Record boot
    record_info('OS boot', 'Successfully booted!');
}

sub test_flags {
    return {fatal => 1, milestone => 0};
}

1;
