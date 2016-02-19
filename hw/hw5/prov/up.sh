# bring up machines
#vagrant up --no-provision --provider softlayer

# make hosts file
cat > hosts_default <<EOF
127.0.0.1   localhost localhost.localdomain localhost4 localhost4.localdomain4
::1         localhost localhost.localdomain localhost6 localhost6.localdomain6
EOF
slcli vs list --columns backend_ip,hostname,domain \
    | perl -pe 's/^(.+)  (.+)  (.+)$/$1\t$2  $2.$3/' \
	   >> hosts_default
awk '{print $2;}' hosts_default | grep -v localhost > hadoop_conf/slaves

# make and distribute keys
rm -rf ssh-keys
mkdir -p ssh-keys
ssh-keygen -t ed25519 -C hadoop -f ssh-keys/id_ed25519
for host in `slcli vs list --columns primary_ip,hostname | cut -f1 -d' '`; do
    ssh root@$host 'for k in /etc/ssh/*.pub; do echo $(hostname) $(cat $k); done'
done \
    > ssh-keys/known_hosts

for host in `slcli vs list --columns primary_ip,hostname | cut -f1 -d' '`; do
    ssh -o ControlMaster=auto -o ControlPath="~/.ssh/sockets/%r@%h-%p" -o ControlPersist=600 \
	root@$host \
	'yum -y install perl'
    ssh -o ControlMaster=auto -o ControlPath="~/.ssh/sockets/%r@%h-%p" -o ControlPersist=600 \
	root@$host \
	'perl -pi -e "s/(Defaults[[:space:]]*requiretty)/# $1/" /etc/sudoers'
done

# set up aws keys for s3a filesystem uris
eval `grep -A2 s3-only ~/.aws/credentials | tail -2`
cat > hadoop_conf/core-site.xml <<EOF
<configuration>
  <property> 
    <name>fs.default.name</name> 
    <value>hdfs://master:9000/</value> 
  </property> 
  <property> 
    <name>dfs.permissions</name> 
    <value>false</value> 
  </property> 
  <property>
    <name>hadoop.tmp.dir</name>
    <value>/tmp</value>
  </property>

  <property>
    <name>fs.s3a.access.key</name>
    <value>${aws_access_key_id}</value>
  </property>
  <property>
    <name>fs.s3a.secret.key</name>
    <value>${aws_secret_access_key}</value>
  </property>
</configuration>
EOF

# run provision scripts
vagrant provision
