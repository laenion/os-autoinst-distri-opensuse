# SUSE's openQA tests
#
# Copyright © 2019 SUSE LLC
#
# Copying and distribution of this file, with or without modification,
# are permitted in any medium without royalty provided the copyright
# notice and this notice are preserved.  This file is offered as-is,
# without any warranty.

# Summary: it covers basic lvm commands
# pvcreate vgcreate lvcreate
# pvdisplay vgdisplay lvdisplay
# vgextend lvextend
# pvmove vgreduce
# pvremove vgremove lvremove
# - Choose test disk
# - Install lvm2 and xfsprogs
# - Partition test disk
# - Create a pv and display result
# - Create a vg and display result
# - Create a lv and display result
# - Create a xfs fs
# - Mount, create a test file, check and umount
# - Create a second pv and display result
# - Extend the created pv
# - Extend first lv to 1020M
# - Mount and check test file
# - Extend xfs filesystem and check test file and fs size
# - Create a third pv and extend
# - Move data from first pv to third
# - Remove old pv
# - Check data from test file
# - Cleanup
# Maintainer: Paolo Stivanin <pstivanin@suse.com>

use base "consoletest";
use strict;
use warnings;
use testapi;
use version_utils;
use utils 'zypper_call';

sub set_playground_disk {
    # TODO check which vda is unpartitioned and use that one
    unless (get_var('PLAYGROUNDDISK')) {
        my $vd = 'vd';    # KVM
        if (check_var('VIRSH_VMM_FAMILY', 'xen')) {
            $vd = 'xvd';
        }
        elsif (check_var('VIRSH_VMM_FAMILY', 'hyperv') or check_var('VIRSH_VMM_FAMILY', 'vmware')) {
            $vd = 'sd';
        }
        assert_script_run 'parted --script --machine -l';
        my $unpartitioned_device = script_output("parted --script --machine -l 2>/dev/null | grep unknown | cut -f1 -d':' | grep /dev/$vd");
        validate_script_output("echo $unpartitioned_device", sub { /\/dev\/$vd[ab]/ });
        set_var('PLAYGROUNDDISK', $unpartitioned_device);
    }
}

sub run {
    my ($self) = @_;

    select_console 'root-console';

    $self->set_playground_disk;
    my $disk = get_required_var('PLAYGROUNDDISK');
    record_info("Information", "The playground disk used by this test is: $disk");

    zypper_call 'in lvm2';
    zypper_call 'in xfsprogs';

    # Create 3 partitions
    assert_script_run 'echo -e "g\nn\n\n\n+1G\nt\n8e\nn\n\n\n+1G\nt\n2\n8e\nn\n\n\n\nt\n\n8e\np\nw" | fdisk ' . $disk;
    assert_script_run 'lsblk';

    my $timeout = 180;

    # Create pv vg lv
    validate_script_output("pvcreate ${disk}1",             sub { m/successfully created/ }, $timeout);
    validate_script_output("pvdisplay",                     sub { m/${disk}1/ },             $timeout);
    validate_script_output("vgcreate test ${disk}1",        sub { m/successfully created/ }, $timeout);
    validate_script_output("vgdisplay test",                sub { m/test/ },                 $timeout);
    validate_script_output("lvcreate -n one -L 1020M test", sub { m/created/ },              $timeout);
    validate_script_output("lvdisplay",                     sub { m/one/ },                  $timeout);

    # create a fs
    assert_script_run 'mkfs -t xfs /dev/test/one';
    assert_script_run 'mkdir /mnt/test_lvm';
    assert_script_run 'mount /dev/test/one /mnt/test_lvm';
    assert_script_run 'echo test > /mnt/test_lvm/test';
    assert_script_run 'cat /mnt/test_lvm/test|grep test';
    assert_script_run 'umount /mnt/test_lvm';

    # extend test volume group
    validate_script_output("pvcreate ${disk}2",      sub { m/successfully created/ },  $timeout);
    validate_script_output("pvdisplay",              sub { m/${disk}2/ },              $timeout);
    validate_script_output("vgextend test ${disk}2", sub { m/successfully extended/ }, $timeout);

    # extend one logical volume with the new space
    validate_script_output("lvextend -L +1020M /dev/test/one", sub { m/successfully resized/ }, $timeout);
    assert_script_run 'mount /dev/test/one /mnt/test_lvm';
    assert_script_run 'cat /mnt/test_lvm/test | grep test';

    # extend the filesystem
    validate_script_output("xfs_growfs /mnt/test_lvm", sub { m/data blocks changed/ }, $timeout);
    validate_script_output("df -h /mnt/test_lvm",      sub { m/test/ },                $timeout);
    validate_script_output("cat /mnt/test_lvm/test",   sub { m/test/ });

    # move data from the original extend to the new one
    validate_script_output("pvcreate ${disk}3",      sub { m/successfully created/ },  $timeout);
    validate_script_output("vgextend test ${disk}3", sub { m/successfully extended/ }, $timeout);
    # JeOS kernel does not come with all device mapper modules
    # it tends to keep dm modules tree simple
    # dm-mirror module is missing -> pvmove operation always fails on JeOS images
    unless (is_jeos) {
        assert_script_run "pvmove ${disk}1 ${disk}3";
        # after moving data, remove the old extend with no data
        validate_script_output("vgreduce test ${disk}1", sub { m/Removed/ }, $timeout);
    }

    # check the data just to be sure
    validate_script_output("cat /mnt/test_lvm/test", sub { m/test/ });

    # remove all
    assert_script_run 'umount /mnt/test_lvm';
    validate_script_output("lvremove -y /dev/test/one", sub { m/successfully removed/ }, $timeout);
    assert_script_run 'lvdisplay';
    validate_script_output("vgremove -y test", sub { m/successfully removed/ }, $timeout);
    assert_script_run 'vgdisplay';
    validate_script_output("pvremove -y ${disk}1 ${disk}2 ${disk}3", sub { m/successfully wiped/ }, $timeout);
    assert_script_run 'pvdisplay';
}

1;
