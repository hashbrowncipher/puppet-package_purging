# Class: package_purging::config
# ===========================
#
# Manages APT config settings
#
# Parameters
# ----------
#
# * `apt_conf_d_filename`
# Which filename, under /etc/apt.conf.d/, to store the settings in.
# If `undef`, the file won't be created.
#
class package_purging::config(
  $apt_conf_d_filename = '90always_purge',
) {

  if $apt_conf_d_filename {
    file {"/etc/apt/apt.conf.d/${apt_conf_d_filename}":
      ensure  => file,
      owner   => 'root',
      group   => 'root',
      mode    => '0644',
      content => "APT::Get::Purge \"true\";\n",
    }
  }

}
