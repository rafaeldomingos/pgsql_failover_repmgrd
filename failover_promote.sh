#!/bin/bash

echo "$(date) - Script chamado" >> /var/log/postgresql/repmgr.log

# Argumentos passados para o script.
up_id=$1
name=$2
pgsql_ver=16

vip="172.20.30.199"  # IP virtual/flutuante a ser movido.
iface="ens192"       # Interface de rede para o IP virtual

# Caminhos absolutos dos comandos
IP_CMD="/sbin/ip"
ARPING_CMD="/usr/sbin/arping"
SSH_CMD="/usr/bin/ssh"
SYSTEMCTL_CMD="/bin/systemctl"
SU_CMD="/usr/bin/su"
SUDO_CMD="/usr/bin/sudo"

${SUDO_CMD} echo "$(date) - Argumentos recebidos: up_id=$up_id, name=$name" >> /var/log/postgresql/repmgr.log

# Imprime os valores das variáveis
${SUDO_CMD} echo "$(date) - Variáveis: pgsql_ver=$pgsql_ver, vip=$vip, iface=$iface" >> /var/log/postgresql/repmgr.log
${SUDO_CMD} echo "$(date) - Comandos: IP_CMD=$IP_CMD, ARPING_CMD=$ARPING_CMD, SSH_CMD=$SSH_CMD, SYSTEMCTL_CMD=$SYSTEMCTL_CMD, SU_CMD=$SU_CMD" >> /var/log/postgresql/repmgr.log

# Verifica se o evento é 'standby_promote'.
if [ "$name" == "standby_promote" ]; then
    ${SUDO_CMD} echo "$(date) - Evento standby_promote detectado" >> /var/log/postgresql/repmgr.log
    
    declare -A servers

    if [ "$up_id" == "1" ]; then
        down_id=2
    else
        down_id=1
    fi

    servers[2]="172.20.30.220"
    servers[1]="172.20.30.218"

    ${SUDO_CMD} echo "$(date) - Mapeamento de servidores: ${servers[@]}" >> /var/log/postgresql/repmgr.log
    ${SUDO_CMD} echo "$(date) - IDs: up_id=$up_id, down_id=$down_id" >> /var/log/postgresql/repmgr.log

    ${SUDO_CMD} echo "$(date) - Tentando estabelecer conexão SSH com o nó ${servers[$down_id]}" >> /var/log/postgresql/repmgr.log
	${SUDO_CMD} echo 
    while [[ $(${SSH_CMD} -o ConnectTimeout=5 postgres@${servers[$down_id]} echo ok 2>&1) != "ok" ]]; do
        ${SUDO_CMD} sleep 2
        ${SUDO_CMD} echo "$(date) - Nó ${servers[$down_id]} inacessível" >> /var/log/postgresql/repmgr.log
    done
    ${SUDO_CMD} echo "$(date) - Conexão SSH com o nó ${servers[$down_id]} estabelecida" >> /var/log/postgresql/repmgr.log

     # Adiciona o IP virtual no nó principal:
    ${SUDO_CMD} echo "$(date) - Adicionando IP virtual $vip ao nó principal" >> /var/log/postgresql/repmgr.log
    ${SUDO_CMD} ${IP_CMD} addr add ${vip}/24 dev ${iface}
    ${SUDO_CMD} ${IP_CMD} link set ${iface} up
    ${SUDO_CMD} ${ARPING_CMD} -q -c 3 -A ${vip} -I ${iface}
    ${SUDO_CMD} echo "$(date) - IP virtual $vip adicionado ao nó principal" >> /var/log/postgresql/repmgr.log

    # Executa comandos no nó que falhou
    ${SUDO_CMD} echo "$(date) - Removendo IP virtual $vip do nó falho" >> /var/log/postgresql/repmgr.log
    ${SSH_CMD} -T ${servers[$down_id]} "${SUDO_CMD} ${IP_CMD} addr del ${vip}/24 dev ${iface}" 2>/dev/null || true
    ${SUDO_CMD} echo "$(date) - IP virtual $vip removido do nó falho" >> /var/log/postgresql/repmgr.log

    ${SUDO_CMD} echo "$(date) - Executando comandos de failover no nó falho" >> /var/log/postgresql/repmgr.log
    
	
	#${SSH_CMD} -T ${servers[$down_id]} <<EOF
    #    ${SUDO_CMD} echo "$(date) - Parando serviço do PostgreSQL" >> /var/log/postgresql/repmgr.log
    #    ${SUDO_CMD} ${SYSTEMCTL_CMD} stop postgresql
    #    ${SUDO_CMD} echo "$(date) - Limpando diretório de dados do PostgreSQL" >> /var/log/postgresql/repmgr.log
    #    ${SUDO_CMD} ${SU_CMD} - postgres -c "rm -rf /var/lib/postgresql/${pgsql_ver}/main/*"
    #    ${SUDO_CMD} echo "$(date) - Clonando configuração do nó ativo" >> /var/log/postgresql/repmgr.log
    #    ${SUDO_CMD} ${SU_CMD} - postgres -c "repmgr --force -h '${servers[$up_id]}' -d repmgr -U repmgr standby clone"
	#	${SUDO_CMD} Sleep 2
	#	${SUDO_CMD} ${SYSTEMCTL_CMD} start postgresql"
     #   ${SUDO_CMD} sleep 2
     #   ${SUDO_CMD} echo "$(date) - Registrando nó no cluster repmgr" >> /var/log/postgresql/repmgr.log
     #   ${SUDO_CMD} ${SU_CMD} - postgres -c "repmgr standby register -F"
#EOF
SUDO_CMD="sudo"

	${SSH_CMD} -T ${servers[$down_id]} "${SUDO_CMD} sh -c '\
		echo \"\$(date) - Parando serviço do PostgreSQL\" && \
		${SYSTEMCTL_CMD} stop postgresql && \
		echo \"\$(date) - Limpando diretório de dados do PostgreSQL\" && \
		${SUDO_CMD} -u postgres rm -rf /var/lib/postgresql/${pgsql_ver}/main/* && \
		echo \"\$(date) - Clonando configuração do nó ativo\" && \
		${SUDO_CMD} -u postgres repmgr --force -h ${servers[$up_id]} -d repmgr -U repmgr standby clone && \
		sleep 2 && \
		${SYSTEMCTL_CMD} start postgresql && \
		sleep 2 && \
		echo \"\$(date) - Registrando nó no cluster repmgr\" && \
    ${SUDO_CMD} -u postgres repmgr standby register -F \
	'"


    ${SUDO_CMD} echo "$(date) - Processo de failover para ${servers[$up_id]} completado." >> /var/log/postgresql/repmgr.log
else
    ${SUDO_CMD} echo "$(date) - Evento $name não é standby_promote. Nenhuma ação tomada." >> /var/log/postgresql/repmgr.log
fi

