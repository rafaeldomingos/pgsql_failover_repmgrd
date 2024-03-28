# Replicação PostgreSQL 16 com Repmgrd

## Versões de Referência:
- PostgreSQL 16
- Repmgrd 5.4.1
- Debian 12

Considerando duas máquinas, master e slave.

### 1. Instalação dos pacotes em ambos os servidores:

```bash
apt update -y && apt upgrade -y
sudo apt -y install gnupg2
curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo gpg --dearmor -o /etc/apt/trusted.gpg.d/postgresql.gpg
echo "deb http://apt.postgresql.org/pub/repos/apt/ `lsb_release -cs`-pgdg main" | sudo tee /etc/apt/sources.list.d/pgdg.list
apt install rsync postgresql-16 postgresql-16-repmgr repmgr
apt install gcc
apt install make
apt install postgresql-server-dev-16
cd /usr/share/postgresql/16/extension/
sudo git clone https://github.com/petere/plsh.git
cd plsh/
sudo make install PG_CONFIG=/usr/bin/pg_config
ln -s /usr/lib/postgresql/16/bin/pg_ctl /usr/bin/pg_ctl
echo "postgres ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers
```

### 2. Configuração do "/etc/postgresql/16/main/postgresql.conf"

```plaintext
listen_addresses = '*'
ssl = off
shared_preload_libraries = 'repmgr'
max_wal_senders = 20
max_replication_slots = 15
wal_level = 'replica'
hot_standby = on
archive_mode = on
archive_command = '/bin/true'
```

### 3. Configuração do "/etc/postgresql/16/main/pg_hba.conf"

```plaintext
# Database administrative login by Unix domain socket
local all postgres trust

# TYPE DATABASE USER ADDRESS METHOD

# "local" is for Unix domain socket connections only
local all all trust
# IPv4 local connections:
host all all 127.0.0.1/32 trust
host all all 192.168.50.0/24 trust
host all all 172.16.0.0/24 trust
host all all 172.20.30.0/24 trust
# IPv6 local connections:
host all all ::1/128 trust
# Allow replication connections from localhost, by a user with the
# replication privilege.
local replication all trust
host replication all 127.0.0.1/32 trust
host replication all 172.20.30.0/24 trust
host replication all ::1/128 trust
```

#### 3.1 Reiniciar PostgreSQL

```bash
service postgresql restart
```

### APENAS NO NODE1:

#### 4. Configuração do Repmgrd

```plaintext
vim "/etc/repmgr.conf"

node_id=1
node_name=node1
conninfo='host=172.20.30.218 user=repmgr dbname=repmgr'
failover=automatic
promote_command='repmgr standby promote -f /etc/repmgr.conf --log-to-file'
follow_command='repmgr standby follow -f /etc/repmgr.conf --log-to-file'
log_file='/var/log/postgresql/repmgr.log'
log_level=DEBUG
reconnect_attempts=4
reconnect_interval=5
data_directory='/var/lib/postgresql/16/main'
ssh_options='-q -o ConnectTimeout=10'
```

##### 4.1 Configuração do serviço repmgrd

```plaintext
vim "/etc/default/repmgrd"

REPMGRD_ENABLED=yes
REPMGRD_CONF="/etc/repmgr.conf"
```

#### 5. Criar usuários e banco repmgr:

```bash
su - postgres -c 'createuser --replication --createdb --createrole --superuser repmgr && createdb repmgr -O repmgr'
service repmgrd restart
```

#### 6. Registrar o primário:

```bash
su - postgres -c 'repmgr primary register'
```

##### 6.1 Verificar o cluster:

```bash
su - postgres -c 'repmgr cluster show'
```

### NO NODE2:

#### 7. Configuração do Repmgrd

```plaintext
vim "/etc/repmgr.conf"

node_id=2
node_name=node2
conninfo='host=172.20.30.220 user=repmgr dbname=repmgr'
failover=automatic
promote_command='repmgr standby promote -f /etc/repmgr.conf --log-to-file'
follow_command='repmgr standby follow -f /etc/repmgr.conf --log-to-file'
log_file='/var/log/postgresql/repmgr.log'
log_level=DEBUG
reconnect_attempts=4
reconnect_interval=5
data_directory='/var/lib/postgresql/16/main'
ssh_options='-q -o ConnectTimeout=10'
```

##### 7.1 Configuração do serviço repmgrd

```plaintext
vim "/etc/default/repmgrd"

REPMGRD_ENABLED=yes
REPMGRD_CONF="/etc/repmgr.conf"
```

#### 8. Registrar o standby:

```bash
service postgresql stop
su - postgres -c "rm -rf /var/lib/postgresql/16/main/*"
su - postgres -c "repmgr -h 172.20.30.218 -U repmgr -d repmgr --force standby clone"
service postgresql start
su - postgres -c "repmgr standby register -F"
```

### APÓS AS CONFIGURAÇÕES

A saída do comando `repmgr cluster show` deve ser algo parecido com isto:

```plaintext
 ID | Name  | Role    | Status    | Upstream | Location | Priority | Timeline | Connection string
----+-------+---------+-----------+----------+----------+----------+----------+----------------------------------------------
 1  | node1 | primary | * running |          | default  | 100      | 11       | host=172.20.30.218 user=repmgr dbname=repmgr
 2  | node2 | standby |   running | node1    | default  | 100      | 11       | host=172.20.30.220 user=repmgr dbname=repmgr
```

### CONFIGURAÇÃO DO FAILOVER AUTOMÁTICO

#### APENAS NO NODE1 QUE ESTIVER COMO PRIMÁRIO

9. Conectar no banco e criar extensão plsh

```bash
psql -U repmgr
CREATE EXTENSION IF NOT EXISTS repmgr;
CREATE EXTENSION plsh;
CREATE FUNCTION failover_promote() RETURNS trigger AS $$
#!/bin/bash
/bin/bash /var/lib/postgresql/failover_promote.sh $1 $2
$$ LANGUAGE plsh;
\q
```

10. Baixar o script:

```bash
curl -o /var/lib/postgresql/failover_promote.sh https://raw.githubusercontent.com/rafaeldomingos/pgsql_failover_repmgrd/main/failover_promote.sh
chown postgres:postgres /var/lib/postgresql/failover_promote.sh
chmod 755 /var/lib/postgresql/failover_promote.sh
```

### EM AMBAS AS MÁQUINAS FAZER O SSH SEM SENHA PRO USUÁRIO POSTGRESQL

11. Providenciar SSH sem senha pro usuário postgresql para ambos os hosts

```bash
sudo su - postgres
mkdir -p ~/.ssh
ssh-keygen -t rsa -N "" -f ~/.ssh/id_rsa
scp ~/.ssh/id_rsa.pub root@IP_DO_OUTRO_NODE:/tmp
```

#### Após gerar e copiar de uma máquina para a outra, em cada uma gerar o arquivo authorized_keys

```bash
cat /tmp/id_rsa.pub >> ~/.ssh/authorized_keys
```

##### 11.1 Testar o acesso SSH de uma máquina para a outra

```bash
su - postgres -c 'ssh -T IP_DO_OUTRO_NODE "sudo ifconfig -a"'
```

### INFORMAÇÕES ADICIONAIS, TODO O PROCESSO SERÁ MOSTRADO NO LOG

```bash
tail -f /var/log/postgresql/repmgr.log
```
