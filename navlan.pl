#!/usr/bin/perl -w
# $Id: navlan.pl,v 1.43 2014/04/15 20:40:39 glb_mvinicius Exp $

# NAVLAN
# Criacao Automatizada de VLANS: 
# Interface CLI

# AUTHOR 
# Marcus Cesario (marcus.vinicius@corp.globo.com) - r. 6443

# Ultimas Atualizacoes:

use strict;
use DBI;
use Data::Dumper;
use English;
use Regexp::Common; 
use Regexp::Common qw( net );
use NetAddr::IP::Lite qw( :aton );
use Net::SNMP qw(INTEGER OCTET_STRING);

# Modulos do sistema
use Controller::Codeman qw( gerarCodigos ); 
use Model::Conf  qw( %campos %amb %amb_conf );
use Model::Validacao qw( 
    valida_IP
    valida_Network
    valida_vlanid
    valida_MaskCIDR
    valida_MaskCIDR_VLAN
    valida_NetParaAmbiente
);

use telco_snmp;

our %campos;
our %amb;
our %amb_conf;
use Model::Conf qw( %amb_ids );

my $debug   = 0;

my $VERSION     = 'v0.0.1a';

my ($CRIAFLAG, $REMOVEFLAG, $ID_VLAN_OU_REDE, $AJUDA, $LISTA_AMB, $AMB_ID, $VLANNAME, $VLAN_NUM);
my $L2FLAG = 0;
my $IPv4FLAG = 0;
my $IPv6FLAG = 0;
my $ID_VLAN;
my $ID_REDEv4;
my $ID_REDEv6;
my $ERROS=0;
my $WARNINGS=0;

my $REDE_VALIDA = '^(([01]?\d?\d|2[0-4]\d|25[0-5])\.){3}([01]?\d?\d|2[0-4]\d|25[0-5])\/(([12]?[0-9])|(3[0-2]))$';

my $ADMIN_EMAIL = 'admin@localhost';

# Telecom DB
my $DATA_SOURCE = 'dbi:mysql:NETWORKAPI_DB;host=NETWORKAPI_DB_HOST:3306';
my $DBUSER = 'DB_USER';
my $DBPASS = 'DB_PASS';

my $DIR_CONF = './generated_config_files';

#---------------- OIDS SNMP CISCO
my $vtpVlanState = '1.3.6.1.4.1.9.9.46.1.3.1.1.2';
my $vtpVlanEditTable = '1.3.6.1.4.1.9.9.46.1.4.2';
my $vtpVlanEditOperation = '1.3.6.1.4.1.9.9.46.1.4.1.1.1';
my $vtpVlanEditBufferOwner = '1.3.6.1.4.1.9.9.46.1.4.1.1.3';
my $vtpVlanEditRowStatus = '1.3.6.1.4.1.9.9.46.1.4.2.1.11';
my $vtpVlanEditType = '1.3.6.1.4.1.9.9.46.1.4.2.1.3';
my $vtpVlanEditName = '1.3.6.1.4.1.9.9.46.1.4.2.1.4';
my $vtpVlanEditDot10Said = '1.3.6.1.4.1.9.9.46.1.4.2.1.6';
my $vtpVlanApplyStatus = '1.3.6.1.4.1.9.9.46.1.4.1.1.2';

#---------------- OIDS SNMP HP PROCURVE
my $dot1qVlanStaticRowStatus = '1.3.6.1.2.1.17.7.1.4.3.1.5';
my $dot1qVlanStaticName = '1.3.6.1.2.1.17.7.1.4.3.1.1';

#---
sub aplica_configuracao_backuper;
sub aplica_configuracao_snmp;
sub equipamento_e_cisco;
sub equipamento_e_hp;
sub exibe_ajuda;
sub existe_equip_nome;
sub get_amb_nome;
sub finaliza;
sub lista_ambientes_id;
sub set_vlan_criada;
sub trata_argumentos;
sub verifica_dados_bd;
sub vlan_ja_existe_cisco;
sub vlan_ja_existe_hp;
sub switch_esta_sendo_alterado;
sub vlan_decimal2dot10said;
sub esta_criado_l2;
#---

# %VAR WAS
#	my %var = (vlan_ambiente=>$amb_ids{$AMB_ID},
#				vlan_amb_nome=> get_amb_nome($AMB_ID),
#				vlan_name=>$VLANNAME,
#				vlan_net=>$rede,
#				vlan_mask=>$bloco,
#				vlan_id=>$VLAN_NUM
#
# NOW IS
# 	my %var = (vlan_ambiente=>$amb_ids{$AMB_ID},
#				vlan_amb_nome=> get_amb_nome($AMB_ID),
#				flags=>((2**0*$L2FLAG)+(2**1*$IPv4FLAG)+(2**2*$IPv6FLAG)),
#				vlan_name=>$VLANNAME,
#				vlan_id=>$ID_VLAN,
#				vlan_id_db=>$ID_VLAN,
#				vlan_net=>$rede,
#				vlan_mask=>$bloco,
#				);


#Execucao do script
#--------------------------------------------------------------------
&trata_argumentos();
my %var = &verifica_dados_bd();

#my @codigos = Controller::Codeman->gerarCodigos(\%var);
my @codigos;

my @equipamentos_a_configurar;
my @equipamentos_a_configurar_l2;

#Executa somente as rotinas de verificacao da Vlan L2
if($L2FLAG){
	@equipamentos_a_configurar_l2 = @{$amb_conf{$var{vlan_ambiente}}{L2}};
	
#Ou das redes L3
}elsif($IPv4FLAG || $IPv6FLAG || $REMOVEFLAG){
	@codigos = Controller::Codeman->gerarCodigos(\%var);
	
	if (@codigos == 0) {
		print "ERRO: Os templates de geracao de codigo para as redes nao executaram corretamente.\n"; 
		$ERROS++;
	} 
	
	foreach my $r ( @codigos ){
		#print "$r->{titulo}\n";
		#print "$r->{conteudo}\n";
		
		# No modulo Conf.pm, o titulo de cada script e o nome do equipamento que devera
		# recever configuracao. Entao, para saber se o conteudo e um script para ser aplicado,
		# verifica se existe equipamento com nome igual ao titulo
		if ( existe_equip_nome($r->{titulo}) ){
			push (@equipamentos_a_configurar, $r->{titulo});
			# Gera arquivo com codigos separados
		
			my $erro=0; 
			print "Gerando arquivo $DIR_CONF/vlan_id-db_$ID_VLAN\_".$r->{titulo}."-conf.txt...";
			open (OUT, ">$DIR_CONF/vlan_id-db_$ID_VLAN\_".$r->{titulo}."-conf.txt") or do{
				print "\n\tERRO: $!\n";
				$ERROS++;
				$erro=1;
			};
			if(!$erro){
				print OUT $r->{conteudo};
				close(OUT);
				chmod 0666, "$DIR_CONF/vlan_id-db_$ID_VLAN\_".$r->{titulo}."-conf.txt";
				print "OK\n";
			} 
			
			print "Gerando arquivo $DIR_CONF/vlan_id-db_$ID_VLAN\_".$r->{titulo}."_remove-conf.txt...";
			open (OUT, ">$DIR_CONF/vlan_id-db_$ID_VLAN\_".$r->{titulo}."_remove-conf.txt") or do{
				print "\n\tERRO: $!\n";
				$ERROS++;
				$erro=1;
			};
			if(!$erro){
				print OUT $r->{conteudo_remove};
				close(OUT);
				chmod 0666, "$DIR_CONF/vlan_id-db_$ID_VLAN\_".$r->{titulo}."_remove-conf.txt";
				print "OK\n";
			} 

		}
	}
}

finaliza() if $ERROS;

print "Configurando equipamentos...\n";
if ($CRIAFLAG){
	
	#Executa somente as rotinas de criacao da Vlan L2
	if($L2FLAG){
		$ERROS++ if !aplica_configuracao_snmp(@equipamentos_a_configurar_l2, \%var);
		finaliza() if $ERROS;
		set_vlan_criada($ID_VLAN, 1);
		
	#Ou as rotinas de criacao da rede em camada 3	
	}elsif($IPv4FLAG || $IPv6FLAG){
		if(!esta_criado_l2($ID_VLAN)){
			if(defined $equipamentos_a_configurar_l2[0]){
				set_vlan_criada($ID_VLAN, 1);
			}
			else{
				$ERROS++ if !aplica_configuracao_snmp(@equipamentos_a_configurar_l2, \%var);
				finaliza() if $ERROS;
				set_vlan_criada($ID_VLAN, 1);
			}
		}
		$ERROS++ if !aplica_configuracao_backuper(@equipamentos_a_configurar);
		finaliza() if $ERROS;
	}
}
elsif($REMOVEFLAG){
	if(esta_criado_l2($ID_VLAN)){
		$ERROS++ if !aplica_configuracao_backuper(@equipamentos_a_configurar);
		set_vlan_criada($ID_VLAN, 0);
		finaliza() if $ERROS;
	}
}
else{
	print "Vlan/Rede nao foi criada nos equipamentos.\n";
}

finaliza();

#--------------------------------------------------------------------

#===  FUNCTION  ================================================================
#         NAME:  aplica_configuracao_backuper
#      PURPOSE:  Aplica os scripts gerados via script backuper (via tftp)
#      RETURNS:  1 se existe, sai do script se não existe.
#===============================================================================
sub aplica_configuracao_backuper(){
	my @equipamentos_a_configurar = @_;

	for my $equipamento (@equipamentos_a_configurar){
		my $arquivo = "";
		if($CRIAFLAG){
			$arquivo = "vlan_id-db_$ID_VLAN\_".$equipamento."-conf.txt";
		}
		elsif($REMOVEFLAG){
			$arquivo = "vlan_id-db_$ID_VLAN\_".$equipamento."_remove-conf.txt";
		}
		print "====== Chamando backuper para aplicar configuracao no \"$equipamento\" ======\n";
		my $output = `/usr/bin/backuper -T acl -O -b '../scripts_vlans/$arquivo' -i $equipamento`;
		if ($output =~ /FALHA/i){
			return 0;
		}
		print $output;
	}
	return 1;
}

#===  FUNCTION  ================================================================
#         NAME:  aplica_configuracao_snmp
#      PURPOSE:  Para equipamentos cisco, cria Vlan L2 via SNMP
#      RETURNS:  1 se ok, 0 se erro
#===============================================================================
sub aplica_configuracao_snmp(){
	my @equipamentos_a_configurar = @_;
	my $snmp_obj = new telco_snmp;
	my $tentativa=1;

	for my $equipamento (@equipamentos_a_configurar){
		if ( equipamento_e_cisco($equipamento) ){
			#Cria Vlan L2 via SNMP
			
			if (!$snmp_obj->configura_acesso_snmp($equipamento, 1)){
				$ERROS++;
				finaliza();
			}
			if (!$snmp_obj->inicio_acesso_snmp()){
				$ERROS++;
				finaliza();
			}		
			#Verifica se vlan ja existe no equipamento
			if ( !vlan_ja_existe_cisco($snmp_obj, $VLAN_NUM) ){
				
				#Verifica se alguem ja esta alterando o switch
				while ($tentativa < 4 && switch_esta_sendo_alterado($snmp_obj)){
					if(switch_esta_sendo_alterado($snmp_obj)){
						print "WARNING: Switch esta sendo alterado($tentativa). Nova tentativa em 5 segundos.\n";
						sleep(5);
						$tentativa++;
					}	
				}
				
				if(switch_esta_sendo_alterado($snmp_obj)){
					print "ERRO: A configuracao do switch $equipamento esta travada. Favor verificar.\n";
					$ERROS++;
					finaliza();
				}
				#Trava a configuracao do switch
				my $snmp_set1 = $snmp_obj->snmp_set_value([$vtpVlanEditOperation.".1", INTEGER, 2]);
				my $snmp_set2 = $snmp_obj->snmp_set_value([$vtpVlanEditBufferOwner.".1", OCTET_STRING, "NaVlan"]);

				#Verifica se lock foi feito				
				if (!$snmp_set1 || !$snmp_set2 || !switch_esta_sendo_alterado($snmp_obj)){
					print "ERRO: Falha ao fazer lock da configuracao do switch $equipamento.\n";
					$ERROS++;
					$snmp_obj->snmp_set_value([$vtpVlanEditOperation.".1", INTEGER, 4]);
					finaliza();
				}			
				
				#Configura dados da Vlan
				my $snmp_set3 = $snmp_obj->snmp_set_value([$vtpVlanEditRowStatus.".1.$VLAN_NUM", INTEGER, 4]);
				my $snmp_set4 = $snmp_obj->snmp_set_value([$vtpVlanEditType.".1.$VLAN_NUM", INTEGER, 1]);
				my $snmp_set5 = $snmp_obj->snmp_set_value([$vtpVlanEditName.".1.$VLAN_NUM", OCTET_STRING, $VLANNAME]);
				my $vlanDot10said = vlan_decimal2dot10said($VLAN_NUM);
				my $snmp_set6 = $snmp_obj->snmp_set_hex($vtpVlanEditDot10Said.".1.$VLAN_NUM", "000$vlanDot10said");
				
				#verifica se configurou ok
				if(!$snmp_set3 || !$snmp_set4 || !$snmp_set5 || !$snmp_set6){
					print "ERRO: Falha ao configurar dados da vlan no switch $equipamento via SNMP.\n";
					$ERROS++;
					#libera configuracao e finaliza
					$snmp_obj->snmp_set_value([$vtpVlanEditOperation.".1", INTEGER, 4]);
					finaliza();
				}
				#Aplica configuracoes				
				else{
					my $snmp_set7 = $snmp_obj->snmp_set_value([$vtpVlanEditOperation.".1", INTEGER, 3]);
				}
				
				#Verifica status do apply
				my $apply_status = $snmp_obj->snmp_get_value($vtpVlanApplyStatus.".1");
				if($apply_status == 3){
					while (($apply_status == 3) && ($tentativa<4)){
						$apply_status = $snmp_obj->snmp_get_value($vtpVlanApplyStatus.".1");
						$tentativa++;
						print "Aguardando fim da configuracao do switch...\n";
						sleep(3);
					}
				}
				if($apply_status != 2){
					print "ERRO: SNMP Apply Status retornou $apply_status. Favor verificar.\n";
					$snmp_obj->snmp_set_value([$vtpVlanEditOperation.".1", INTEGER, 4]);
					$ERROS++;
				}
				
				#Destrava a configuracao do switch
				$snmp_obj->snmp_set_value([$vtpVlanEditOperation.".1", INTEGER, 4]);
				
				#Verifica se Vlan existe no switch
				if (!vlan_ja_existe_cisco($snmp_obj, $VLAN_NUM)){
					print "ERRO: Vlan L2 não criada no equipamento $equipamento.\n";
					$ERROS++;
				}
			}
		}
		elsif ( equipamento_e_hp($equipamento) ){
			#Cria Vlan L2 via SNMP
			
			if (!$snmp_obj->configura_acesso_snmp($equipamento, 1)){
				$ERROS++;
				finaliza();
			}
			if (!$snmp_obj->inicio_acesso_snmp()){
				$ERROS++;
				finaliza();
			}
						#Verifica se vlan ja existe no equipamento
			if ( !vlan_ja_existe_hp($snmp_obj, $VLAN_NUM) ){
				#Configura dados da Vlan
				my $snmp_set3 = $snmp_obj->snmp_set_value([$dot1qVlanStaticRowStatus.".$VLAN_NUM", INTEGER, 5]);
				my $snmp_set4 = $snmp_obj->snmp_set_value([$dot1qVlanStaticRowStatus.".$VLAN_NUM", INTEGER, 1]);
				my $snmp_set5 = $snmp_obj->snmp_set_value([$dot1qVlanStaticName.".$VLAN_NUM", OCTET_STRING, $VLANNAME]);
				
				#verifica se configurou ok
				if(!$snmp_set3 || !$snmp_set4 || !$snmp_set5 ){
					print "ERRO: Falha ao configurar dados da vlan no switch $equipamento via SNMP.\n";
					$ERROS++;
					my $snmp_set4 = $snmp_obj->snmp_set_value([$dot1qVlanStaticRowStatus.".$VLAN_NUM", INTEGER, 6]);
					finaliza();
				}
				my @cmd = ("configurador -i $equipamento -T snmp_vlans_trunk -A \'\"int=21 add=$VLAN_NUM\"\'");
				my $status_erro = system(@cmd);
				if ($status_erro){
					print "ERRO: Falha ao adicionar vlan no switch $equipamento na porta 21 via SNMP.\n";
					$ERROS++;
					finaliza();
				}
				@cmd = ("configurador -i $equipamento -T snmp_vlans_trunk -A \'\"int=22 add=$VLAN_NUM\"\'");
				$status_erro = system(@cmd);
				if ($status_erro){
					print "ERRO: Falha ao adicionar vlan no switch $equipamento na porta 22 via SNMP.\n";
					$ERROS++;
					finaliza();
				}			
					
			}
		}	
		
	}
	return 0 if $ERROS;
	return 1;
}


#===  FUNCTION  ================================================================
#         NAME:  vlan_decimal2dot10said
#      PURPOSE:  transforma o numero da vlan no valor do dot2said esperado
#      RETURNS:  1 se ok, 0 se erro
#===============================================================================
sub vlan_decimal2dot10said{
	my $vlan = shift;
	
	my $valor = $vlan+100000;
	my $hex = sprintf("%x", $valor); 
	
	return $hex;
}

#===  FUNCTION  ================================================================
#         NAME:  switch_esta_sendo_alterado
#      PURPOSE:  Verifica se equipamento esta trabado para edicao
#      RETURNS:  1 se ok, 0 se erro
#===============================================================================
sub switch_esta_sendo_alterado{
	my $snmp = shift;
	
	my $result = $snmp->snmp_walk($vtpVlanEditTable);
	if ($result) {
		return 1;
	}
	return 0;
}

#===  FUNCTION  ================================================================
#         NAME:  vlan_ja_existe_cisco
#      PURPOSE:  Verifica se vlan ja esta criada no equipamento
#      RETURNS:  1 se ok, 0 se erro
#===============================================================================
sub vlan_ja_existe_cisco{
	my $snmp = shift;
	my $vlan_num = shift;
	
	my $vlan_states = $snmp->snmp_walk($vtpVlanState);
	if(defined %$vlan_states){
		foreach my $vlan_state (keys %$vlan_states) {
			my $vlan = (split(/\./, $vlan_state))[-1];
			return 1 if ($vlan == $vlan_num);	
		}	
	}
	return 0;
}

#===  FUNCTION  ================================================================
#         NAME:  vlan_ja_existe_hp
#      PURPOSE:  Verifica se vlan ja esta criada no equipamento
#      RETURNS:  1 se ok, 0 se erro
#===============================================================================
sub vlan_ja_existe_hp{
	my $snmp = shift;
	my $vlan_num = shift;
	
	my $vlan_states = $snmp->snmp_walk($dot1qVlanStaticRowStatus);
	if(defined %$vlan_states){
		foreach my $vlan_state (keys %$vlan_states) {
			my $vlan = (split(/\./, $vlan_state))[-1];
			return 1 if ($vlan == $vlan_num);	
		}	
	}
	return 0;
}


#===  FUNCTION  ================================================================
#         NAME:  equipamento_e_cisco
#      PURPOSE:  Verifica se equipamento é cisco
#      RETURNS:  1 se ok, 0 se não
#===============================================================================
sub equipamento_e_cisco(){
	my $equipamento = shift;
	
	my $dbh = DBI->connect($DATA_SOURCE, $DBUSER, $DBPASS
        	) || die "Impossivel conectar ao BD: $DBI::errstr";

	my $sth = $dbh->prepare('SELECT TRUE 
							FROM equipamentos e, modelos mo, marcas
							WHERE marcas.id_marca = mo.id_marca
							AND mo.id_modelo = e.id_modelo
							AND marcas.nome = \'cisco\'
							AND e.nome = \''.$equipamento.'\'
							');
	$sth->execute() || die "ERRO na consulta ao BD.";
	
	my ($resp) = $sth->fetchrow_array;
	return 1 if ($resp);
	return 0;

}

#===  FUNCTION  ================================================================
#         NAME:  equipamento_e_hp
#      PURPOSE:  Verifica se equipamento e hp
#      RETURNS:  1 se ok, 0 se não
#===============================================================================
sub equipamento_e_hp(){
	my $equipamento = shift;
	
	my $dbh = DBI->connect($DATA_SOURCE, $DBUSER, $DBPASS
        	) || die "Impossivel conectar ao BD: $DBI::errstr";

	my $sth = $dbh->prepare('SELECT TRUE 
							FROM equipamentos e, modelos mo, marcas
							WHERE marcas.id_marca = mo.id_marca
							AND mo.id_modelo = e.id_modelo
							AND marcas.nome = \'HP\'
							AND e.nome = \''.$equipamento.'\'
							');
	$sth->execute() || die "ERRO na consulta ao BD.";
	
	my ($resp) = $sth->fetchrow_array;
	return 1 if ($resp);
	return 0;

}

#===  FUNCTION  ================================================================
##         NAME:  lista_ambientes_id()
##      PURPOSE:  Imprime na tela ambientes e seus IDs 
##      RETURNS:  nada 
##===============================================================================
sub lista_ambientes_id(){
	my $dbh = DBI->connect($DATA_SOURCE, $DBUSER, $DBPASS
        	) || die "Impossivel conectar ao BD: $DBI::errstr";

	my $sth = $dbh->prepare('SELECT a.id_ambiente, concat(ddc.nome, \'-\', al.nome, \'-\', gl3.nome) 
							FROM ambiente a, ambiente_logico al, divisao_dc ddc, grupo_l3 gl3
							WHERE a.id_grupo_l3 = gl3.id_grupo_l3
							AND a.id_ambiente_logic = al.id_ambiente_logic
							AND a.id_divisao = ddc.id_divisao
							ORDER BY ddc.nome, al.nome, gl3.nome;');
	$sth->execute() || die "ERRO na consulta ao BD.";
	
	my ($id, $amb);
	print "\nListando ambientes cadastrados no BD.\n";
	print "-------------\n";
	print "ID - AMBIENTE\n";
	print "-------------\n";	
	while(($id, $amb)=$sth->fetchrow_array){
		print "$id - $amb\n";
	}
}

#===  FUNCTION  ================================================================
##         NAME:  lista_ambientes_id()
##      PURPOSE:  Imprime na tela ambientes e seus IDs 
##      RETURNS:  nada 
##===============================================================================
sub get_amb_nome{
	my $ambiente_id = shift;
	my $dbh = DBI->connect($DATA_SOURCE, $DBUSER, $DBPASS
        	) || die "Impossivel conectar ao BD: $DBI::errstr";

	my $sth = $dbh->prepare('SELECT concat(ddc.nome, \'-\', al.nome, \'-\', gl3.nome) 
							FROM ambiente a, ambiente_logico al, divisao_dc ddc, grupo_l3 gl3
							WHERE a.id_grupo_l3 = gl3.id_grupo_l3
							AND a.id_ambiente_logic = al.id_ambiente_logic
							AND a.id_divisao = ddc.id_divisao
							AND a.id_ambiente  = '.$ambiente_id);
	$sth->execute() || die "ERRO na consulta ao BD.";
	
	my ($amb) = $sth->fetchrow_array;
	return $amb if ($amb);
	return 0;
}

#===  FUNCTION  ================================================================
##         NAME:  lista_ambientes_id()
##      PURPOSE:  Imprime na tela ambientes e seus IDs 
##      RETURNS:  nada 
##===============================================================================
sub existe_equip_nome{
	my $nome_equip = shift;
	my $dbh = DBI->connect($DATA_SOURCE, $DBUSER, $DBPASS
        	) || die "Impossivel conectar ao BD: $DBI::errstr";

	my $sth = $dbh->prepare('SELECT true 
							FROM equipamentos e
							WHERE e.nome=\''.$nome_equip.'\'
							');
	$sth->execute() || die "ERRO na consulta ao BD.";
	
	my ($existe_equip) = $sth->fetchrow_array;
	return 1 if ($existe_equip);
	return 0;
}


#===  FUNCTION  ================================================================
##         NAME:  set_vlan_criada()
##      PURPOSE:  Update na variavel de controle ativada do BD 
##      RETURNS:  nada 
##===============================================================================
sub set_vlan_criada{
	my $vlan_id = shift;
	my $valor = shift;
	
	my $dbh = DBI->connect($DATA_SOURCE, $DBUSER, $DBPASS
        	) || die "Impossivel conectar ao BD: $DBI::errstr";

	my $sth = $dbh->prepare('UPDATE vlans set ativada='.$valor.'
							WHERE id_vlan='.$vlan_id.' LIMIT 1
							');
	$sth->execute() || die "ERRO na consulta ao BD.";
	
	return 1;
}

#===  FUNCTION  ================================================================
##         NAME:  trata_argumentos()
##      PURPOSE:  tratar argumentos e parametros passado pela linha de comando 
##      RETURNS:  um monte de variavel global devidamente setada... 
##===============================================================================
sub trata_argumentos() {

	use Getopt::Long;
	my @info;

	GetOptions("cria"=>\$CRIAFLAG,
		"remove"=>\$REMOVEFLAG,
		"I=i"=>\$ID_VLAN_OU_REDE,
		"ajuda"=>\$AJUDA,
		"help"=>\$AJUDA,
		"L2"=>\$L2FLAG,
		"IPv4"=>\$IPv4FLAG,
		"IPv6"=>\$IPv6FLAG,
		"lista"=>\$LISTA_AMB
		);

	if ($AJUDA) {
		exibe_ajuda();
		finaliza();
	}
	elsif( $LISTA_AMB ){
		lista_ambientes_id();
		finaliza();
	}
	elsif( !$ID_VLAN_OU_REDE ){
		print "ERRO: Falta o identificador da vlan ou rede. Para ajuda utilize opcao --help.\n";
		$ERROS++;
	}

	if( !$L2FLAG && !$IPv4FLAG && !$IPv6FLAG && !$REMOVEFLAG){
		print "ERRO: Informacoes incompletas. Para ajuda utilize opcao --help.\n";
		$ERROS++;
	}
		
	print "ERRO: Parametro(s) nao reconhecido(s):\n" if $ARGV[0];
	foreach (@ARGV) {
		print "$_\n";
		$ERROS++;
	}
	
	finaliza() if ($ERROS);
	
}

#===  FUNCTION  ================================================================
##         NAME:  esta_criado_l2()
##      PURPOSE:  Verificar se a vlan L2 ja esta criada 
##      RETURNS:  Boolean
##===============================================================================
sub esta_criado_l2{
	
	my $id_vlan = shift;
	
	my $dbh = DBI->connect($DATA_SOURCE, $DBUSER, $DBPASS
        	) || die "Impossivel conectar ao BD: $DBI::errstr";
    my @response;
    
	#Verifica se vlan esta cadastrada no BD
	my $sth = $dbh->prepare('SELECT v.ativada FROM vlans v WHERE v.id_vlan = '.$id_vlan);
	$sth->execute() || die "ERRO na consulta ao BD.";
	
	@response = $sth->fetchrow_array;
	
	return( $response[0] );	

}

#===  FUNCTION  ================================================================
##         NAME:  obtem_dados_l2()
##      PURPOSE:  Pega os dados no BD necessarios para criar vlan em L2 
##      RETURNS:  array com $ID_VLAN, $AMB_ID, $VLANNAME
##===============================================================================
sub obtem_dados_l2{
	
	my $id_vlan = shift;
	
	my $dbh = DBI->connect($DATA_SOURCE, $DBUSER, $DBPASS
        	) || die "Impossivel conectar ao BD: $DBI::errstr";
    my @response;
    
	#Verifica se vlan esta cadastrada no BD
	my $sth = $dbh->prepare('SELECT v.id_vlan, a.id_ambiente, v.nome, v.num_vlan FROM vlans v, ambiente a
							WHERE id_vlan = '.$id_vlan.'
							AND a.id_ambiente = v.id_ambiente
							');
	$sth->execute() || die "ERRO na consulta ao BD.";
	
	@response = $sth->fetchrow_array;
	
	if (!$response[0]){
		print "ERRO: Nao existe VLAN cadastrada com ID $ID_VLAN_OU_REDE.\n";
		$ERROS++;
		finaliza();
	}
	
	#Verifica se ja esta ativada 
	$sth = $dbh->prepare('SELECT ativada FROM vlans 
							WHERE id_vlan = '.$id_vlan.'
							');
	$sth->execute() || die "ERRO na consulta ao BD.";
	
	my $ativada = $sth->fetchrow_array;
	if ($ativada){
		print "ERRO: O status da Vlan ja e ATIVADA.\n";
		$ERROS++;
	}

    return @response;
}

#===  FUNCTION  ================================================================
##         NAME:  obtem_dados_ipv4_remove()
##      PURPOSE:  Pega os dados no BD necessarios para remover rede ipv4 na vlan
##      RETURNS:  array com $ID_REDEv4, $AMB_ID, $ID_VLAN, $VLANNAME
##===============================================================================
sub obtem_dados_ipv4_remove{
	
	my $id_vlan = shift;
	
	my $dbh = DBI->connect($DATA_SOURCE, $DBUSER, $DBPASS
        	) || die "Impossivel conectar ao BD: $DBI::errstr";
    my @response;
    
	#Verifica se rede IPv4 esta cadastrada no BD
	my $sth = $dbh->prepare('SELECT v.id_vlan, a.id_ambiente, v.nome, v.num_vlan, r.id FROM redeipv4 r, vlans v, ambiente a
							WHERE v.id_vlan = '.$id_vlan.'
							AND r.id_vlan = v.id_vlan
							AND a.id_ambiente = v.id_ambiente
							');
	$sth->execute() || die "ERRO na consulta ao BD.";
	
	@response = $sth->fetchrow_array;
	
	#Se n�o tem vlan e rede para remover, verificar se tem somente vlan para remover
	if (!$response[0]){
		#Verifica se vlan esta cadastrada no BD
		my $sth = $dbh->prepare('SELECT v.id_vlan, a.id_ambiente, v.nome, v.num_vlan FROM vlans v, ambiente a
								WHERE id_vlan = '.$id_vlan.'
								AND a.id_ambiente = v.id_ambiente
								');
		$sth->execute() || die "ERRO na consulta ao BD.";
		
		@response = $sth->fetchrow_array;
		
		if (!$response[0]){
			print "ERRO: Nao existe rede IPv4 nem VLAN cadastrada com ID $ID_VLAN_OU_REDE.\n";
			$ERROS++;
			finaliza();
		}
		#Completa resposta com zeros para ficar igual resposta de rede abaixo
		push(@response, "0");
		push(@response, "0");
		push(@response, "0");	
		#Remover somente vlan
		$L2FLAG = 1;	
	}
	else{
		my $id_rede = $response[0];
	
		$sth = $dbh->prepare('SELECT concat(rede_oct1,".",rede_oct2,".",rede_oct3,".",rede_oct4), bloco FROM redeipv4
								WHERE redeipv4.id = '.$id_rede.'
								');
		$sth->execute() || die "ERRO na consulta ao BD.";
	
		my ($net,$mask) = $sth->fetchrow_array;
		push(@response, $net);
		push(@response, $mask);
		
	}
	
    return @response;

}

#===  FUNCTION  ================================================================
##         NAME:  obtem_dados_ipv4()
##      PURPOSE:  Pega os dados no BD necessarios para criar rede ipv4 na vlan
##      RETURNS:  array com $ID_REDEv4, $AMB_ID, $ID_VLAN, $VLANNAME
##===============================================================================
sub obtem_dados_ipv4{
	
	my $id_rede = shift;
	
	my $dbh = DBI->connect($DATA_SOURCE, $DBUSER, $DBPASS
        	) || die "Impossivel conectar ao BD: $DBI::errstr";
    my @response;
    
	#Verifica se rede IPv4 esta cadastrada no BD
	my $sth = $dbh->prepare('SELECT r.id, a.id_ambiente, v.id_vlan, v.nome, v.num_vlan FROM redeipv4 r, vlans v, ambiente a
							WHERE r.id = '.$id_rede.'
							AND r.id_vlan = v.id_vlan
							AND a.id_ambiente = v.id_ambiente
							');
	$sth->execute() || die "ERRO na consulta ao BD.";
	
	@response = $sth->fetchrow_array;
	
	if (!$response[0]){
		print "ERRO: Nao existe rede IPv4 cadastrada com ID $ID_VLAN_OU_REDE.\n";
		$ERROS++;
		finaliza();
	}

	$sth = $dbh->prepare('SELECT concat(rede_oct1,".",rede_oct2,".",rede_oct3,".",rede_oct4), bloco FROM redeipv4
							WHERE redeipv4.id = '.$id_rede.'
							');
	$sth->execute() || die "ERRO na consulta ao BD.";

	my ($net,$mask) = $sth->fetchrow_array;
	push(@response, $net);
	push(@response, $mask);

    return @response;

}

#===  FUNCTION  ================================================================
##         NAME:  obtem_dados_ipv6()
##      PURPOSE:  Pega os dados no BD necessarios para criar rede ipv4 na vlan
##      RETURNS:  array com $ID_REDEv6, $AMB_ID, $ID_VLAN, $VLANNAME
##===============================================================================
sub obtem_dados_ipv6{
	
	my $id_rede = shift;
	
	my $dbh = DBI->connect($DATA_SOURCE, $DBUSER, $DBPASS
        	) || die "Impossivel conectar ao BD: $DBI::errstr";
    my @response;

	#Verifica se rede IPv6 esta cadastrada no BD
	my $sth = $dbh->prepare('SELECT r.id, a.id_ambiente, v.id_vlan, v.nome, v.num_vlan FROM redeipv6 r, vlans v, ambiente a
							WHERE r.id = '.$id_rede.'
							AND r.id_vlan = v.id_vlan
							AND a.id_ambiente = v.id_ambiente
							');
	$sth->execute() || die "ERRO na consulta ao BD.";
	
	@response = $sth->fetchrow_array;
	
	if (!$response[0]){
		print "ERRO: Nao existe rede IPv6 cadastrada com ID $ID_VLAN_OU_REDE.\n";
		$ERROS++;
		finaliza();
	}
	
	$sth = $dbh->prepare('SELECT concat(bloco1,":",bloco2,":",bloco3,":",bloco4,":",bloco5,":",bloco6,":",bloco7,":",bloco8),
							 concat(mask_bloco1,":",mask_bloco2,":",mask_bloco3,":",mask_bloco4,":",mask_bloco5,":",mask_bloco6,":",mask_bloco7,":",mask_bloco8) 
							 FROM redeipv6
							WHERE redeipv6.id = '.$id_rede.'
							');
	$sth->execute() || die "ERRO na consulta ao BD.";

	my ($net,$mask) = $sth->fetchrow_array;
	push(@response, $net);
	push(@response, $mask);

	return @response;
}

#===  FUNCTION  ================================================================
##         NAME:  lista_ambientes_id()
##      PURPOSE:  Imprime na tela ambientes e seus IDs 
##      RETURNS:  nada 
#$GERAFLAG, $AMB_ID, $EQUIPS_ALVO, $VLANNAME, $NETWORK, $VLAN_NUM, $AJUDA, $LISTA_AMB
##===============================================================================
sub verifica_dados_bd(){
	my $dbh = DBI->connect($DATA_SOURCE, $DBUSER, $DBPASS
        	) || die "Impossivel conectar ao BD: $DBI::errstr";

	my ($rede, $bloco);
	
	if($L2FLAG){
		($ID_VLAN, $AMB_ID, $VLANNAME, $VLAN_NUM) = obtem_dados_l2($ID_VLAN_OU_REDE);
	}elsif($IPv4FLAG){
		($ID_REDEv4, $AMB_ID, $ID_VLAN, $VLANNAME, $VLAN_NUM, $rede, $bloco) = obtem_dados_ipv4($ID_VLAN_OU_REDE);
	}elsif($IPv6FLAG){
		($ID_REDEv6, $AMB_ID, $ID_VLAN, $VLANNAME, $VLAN_NUM, $rede, $bloco) = obtem_dados_ipv6($ID_VLAN_OU_REDE);		
	}elsif($REMOVEFLAG){
		($ID_VLAN, $AMB_ID, $VLANNAME, $VLAN_NUM, $ID_REDEv4,  $rede, $bloco) = obtem_dados_ipv4_remove($ID_VLAN_OU_REDE);
	}		

	my %var = (vlan_ambiente=>$amb_ids{$AMB_ID},
				vlan_amb_nome=> get_amb_nome($AMB_ID),
				flags=>((2**0*$L2FLAG)+(2**1*$IPv4FLAG)+(2**2*$IPv6FLAG)),
				vlan_name=>$VLANNAME,
				vlan_id=>$VLAN_NUM,
				vlan_id_db=>$ID_VLAN,
				vlan_net=>$rede,
				vlan_mask=>$bloco
				);
				
	return %var;
	
}

#===  FUNCTION  ================================================================
##         NAME:  exibe_ajuda()
##      PURPOSE:  Imprime na tela orientacoes para uso do script
##      RETURNS:  nada
##===============================================================================
sub exibe_ajuda(){
	
	print <<EOF

DataCenter Globo.com - Equipe de Telecom
Script para criacao de Vlans/Redes nos Roteadores/Switches

uso: ./navlan -I <id_vlan> [--L2|--IPv4|--IPv6] --cria

   --help	Exibe esta ajuda
   --ajuda	Exibe esta ajuda

   --lista Lista as vlans cadastradas no BD (em implementacao)
    
   -I      Informa o identificador (da vlan ou da rede) no Banco de Dados
   --L2    (opcional) Cria a vlan sem roteamento, somente em L2 nos switches do ambiente
   --IPv4  (opcional) Cria roteamento da rede IPv4
   --IPv6  (opcional) Cria roteamento da rede IPv6
   --cria  Aplica configuracao nos equipamentos

Mais informacoes e documentacao em:

EOF
	
}

sub finaliza(){
	if($WARNINGS){
		my $warn_number = $WARNINGS;
		print "\nFinalizando execucao com $warn_number WARNING(S) ENCONTRADO(S). Verificar a configuracao dos equipamentos.\n";
		print "Em caso de duvidas, informe $ADMIN_EMAIL enviando o(s) warning(s).\n";
	}
	if($ERROS){
		my $erros_number = $ERROS;
		print "\nFinalizando execucao com $erros_number ERRO(S) ENCONTRADO(S). Verificar a configuracao dos equipamentos.\n";
		print "Em caso de duvidas, informe $ADMIN_EMAIL enviando toda a tela de saida com erros.\n";
		exit(1);
	}
	else{
		print "\nExecucao finalizada com sucesso.\n";
		exit(0);
	}
}


