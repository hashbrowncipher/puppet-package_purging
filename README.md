# puppet-package\_purging

This Puppet module houses the native resource type aptly\_purge.

aptly\_purge removes Debian system packages that exist on a Puppet agent, but
are not present in its Puppet catalog. It is designed to ensure that a system
has only those packages specified by the catalog, not any extraneous ones.

aptly\_purge is dependency aware. It synchronizes resources in the Puppet
catalog with those on the host. Packages in the catalog are marked as manually
installed, and those not in the catalog are marked as automatically installed.
Then it simulates a run of the autoremover, capturing the output and generating
Puppet `ensure=>absent` resources.

## Usage

Usage is as follows. Unless `APT::Get::Purge` is set to `true`, it'll take two Puppet
runs for `aptly_purge` to know which packages can be purged.

~~~~
include package_purging::config
aptly_purge { 'packages': }
~~~~

To see what would be removed:

~~~~
include package_purging::config
aptly_purge { 'packages':
  noop => true,
}
~~~~

The superfluous packages will appear in Puppet's output as Package resources to
be removed from the system.

**Note** that aptly\_purge writes into the apt autoremover's database of
auto-installed and manually installed packages, **even when run in noop mode.**
This means that you should not execute `apt-get autoremove` after a no-op
Puppet run and expect sane results.

## Motivating Examples

### Example 1: an old package is left over

A Puppet manifest contains:

~~~~
package { 'java7u45':
  ensure => 'latest',
}
~~~~

An administrator wants java7u75, so they do:

~~~~
package { ['java7u45', 'java7u75':
  ensure => 'latest',
}
~~~~

Once all production uses of 7u45 are gone, the administrator updates their code:

~~~~
package { 'java7u75':
  ensure => 'latest',
}
~~~~

Now java7u45 will remain on existing systems, but newly provisioned systems
will have only the newer package. This can lead to severe cases of "it totally
worked on my dev machine", when code developed on an older dev machine is run
on a newly provisioned production host.

On the other hand, aptly\_purge will automatically remove java7u45 when it is
no longer present in the Puppet catalog.

### Example 2: not-so-temporary temporary packages

An administrator wants to use numactl to gather info about a Cassandra host. They
`apt-get install numactl` "temporarily" so that they can run `numactl --hardware`.

The node does a routine reboot for kernel upgrades. On boot, the Cassandra
initscript automatically uses numactl to change the NUMA policy for the
Cassandra process. As a result this one node is now operating with different
performance characteristics than the rest of its cluster.

aptly\_purge will automatically remove numactl on the next Puppet run, saving
the administrator from having to remember to remove their package. They have
better things to worry about!
