{
  create_zypp_conf: {
    name: 'create zypp.conf',
    content: |||
      #!/usr/bin/env bash
      mkdir -vp /mnt/etc/zypp
      echo '# QE-Yam Test' > /mnt/etc/zypp/zypp.conf
    |||
  }
}
