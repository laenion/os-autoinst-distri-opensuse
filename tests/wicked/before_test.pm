# SUSE's openQA tests
#
# Copyright © 2017-2019 SUSE LLC
#
# Copying and distribution of this file, with or without modification,
# are permitted in any medium without royalty provided the copyright
# notice and this notice are preserved.  This file is offered as-is,
# without any warranty.

# Summary: Do basic checks to make sure system is ready for wicked testing
# Maintainer: Anton Smorodskyi <asmorodskyi@suse.com>

use base 'wickedbase';
use strict;
use warnings;
use testapi;
use utils qw(zypper_call systemctl file_content_replace);
use version_utils 'is_sle';
use network_utils qw(iface setup_static_network);
use serial_terminal;
use main_common 'is_updates_tests';

sub run {
    my ($self, $ctx) = @_;
    $self->select_serial_terminal;
    my @ifaces = split(' ', iface(2));
    die("Missing at least one interface") unless (@ifaces);
    $ctx->iface($ifaces[0]);
    $ctx->iface2($ifaces[1]) if (@ifaces > 1);

    my $enable_command_logging = 'export PROMPT_COMMAND=\'logger -t openQA_CMD "$(history 1 | sed "s/^[ ]*[0-9]\+[ ]*//")"\'';
    my $escaped                = $enable_command_logging =~ s/'/'"'"'/gr;
    assert_script_run("echo '$escaped' >> /root/.bashrc");
    assert_script_run($enable_command_logging);
    # image which we using for sle15 don't have firewall running.
    # QAM need another way to figure out firewall state due to wider set of images
    if (is_sle('<15') || (is_updates_tests() && !script_run('systemctl is-active -q ' . opensusebasetest::firewall))) {
        systemctl("stop " . opensusebasetest::firewall);
        systemctl("disable " . opensusebasetest::firewall);
    }
    assert_script_run('[ -z "$(coredumpctl -1 --no-pager --no-legend)" ]');
    record_info('INFO', 'Setting debug level for wicked logs');
    file_content_replace('/etc/sysconfig/network/config', '--sed-modifier' => 'g', '^WICKED_DEBUG=.*' => 'WICKED_DEBUG="all"', '^WICKED_LOG_LEVEL=.*' => 'WICKED_LOG_LEVEL="debug"');
    #preparing directories for holding config files
    assert_script_run('mkdir -p /data/{static_address,dynamic_address}');
    setup_static_network(ip => $self->get_ip(type => 'host', netmask => 1));
    record_info('INFO', 'Checking that network service is up');
    systemctl('is-active network');
    systemctl('is-active wicked');

    $self->download_data_dir();

    if (check_var('IS_WICKED_REF', '1')) {
        # Common REF Configuration
        record_info('INFO', 'Setup DHCP server');
        zypper_call('--quiet in dhcp-server openvpn', timeout => 200);
        $self->get_from_data('wicked/dhcp/dhcpd.conf', '/etc/dhcpd.conf');
        file_content_replace('/etc/sysconfig/dhcpd', '--sed-modifier' => 'g', '^DHCPD_INTERFACE=.*' => 'DHCPD_INTERFACE="' . $ctx->iface() . '"');
        systemctl 'enable dhcpd.service';
        systemctl 'start dhcpd.service';
    } else {
        # Common SUT Configuration
        if (get_var('WICKED_SOURCES')) {
            zypper_call('--quiet in -t pattern Basis-Devel');
            zypper_call('--quiet in automake autoconf libtool libnl-devel libnl3-devel libiw-devel dbus-1-devel pkg-config libgcrypt-devel systemd-devel git');
            my $repo_url = get_var('WICKED_SOURCES');
            if ($repo_url =~ /\#/) {
                my ($repo_url, $branch) = ($repo_url =~ /(.*)\#(.*)/);
                assert_script_run('git clone ' . $repo_url);
                assert_script_run("git checkout -b $branch origin/$branch");
            }
            else {
                assert_script_run('git clone ' . $repo_url);
            }
            assert_script_run('cd ./wicked ; ./autogen.sh ', timeout => 600);
            assert_script_run('make ; make install',         timeout => 600);
        }
        my $package_list = 'openvswitch openvpn iputils';
        $package_list .= ' libteam-tools libteamdctl0 python-libteam' if check_var('WICKED', 'advanced') || check_var('WICKED', 'aggregate');
        $package_list .= ' gcc' if check_var('WICKED', 'advanced');
        zypper_call('-q in ' . $package_list, timeout => 400);
        $self->reset_wicked();
    }
}

sub test_flags {
    return {fatal => 1, milestone => 1};
}

1;
