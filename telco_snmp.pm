#!/usr/bin/perl

# Pacote com funcoes para criar e verificar configuração de VIPs no F5
# As consultas sao feitas no balanceador configurado na variavel sHost
package telco_snmp;

use DBI;
use Net::SNMP qw(INTEGER OCTET_STRING);
use IPC::Cmd;

sub new
{
	my $obj = {host=>'',
				timeout=>2,
				version=>'v2c',
				community=>'',
				port=>161,
				snmp_session=>0,
				ERROS=>0
				};
	bless ( $obj );
	return $obj;
}

#===  FUNCTION  ================================================================
#         NAME:  configura_acesso_snmp
#      PURPOSE:  iniciar uma conexao snmp com as configuracoes do host
#      RETURNS:  objeto NET::SNMP com conexao ativa
#===============================================================================
sub configura_acesso_snmp(){
	my $self = shift();
	my $equipamento = $_[0];
	my $acesso_rw = $_[1];
	my $host = '';
	my $community_ro = '';

# Telecom DB
my $DATA_SOURCE = 'dbi:mysql:telecom;host=my_db_host:3306';
my $DBUSER = 'db_user';
my $DBPASS = 'db_password';
	
	my $dbh = DBI->connect($DATA_SOURCE, $DBUSER, $DBPASS
        	) || die "Impossivel conectar ao BD: $DBI::errstr";

	my $variavel_acesso = 'ea.pass';
	$variavel_acesso = 'ea.enable_pass' if ($acesso_rw);

	my $sth = $dbh->prepare('SELECT ea.fqdn, '.$variavel_acesso.'
							FROM equiptos_access ea, equipamentos e, tipo_acesso ta
							WHERE e.nome=\''.$equipamento.'\'
							AND ea.id_equip = e.id_equip
							AND ta.protocolo = \'snmp\'
							AND ea.id_tipo_acesso = ta.id_tipo_acesso LIMIT 1');
	$sth->execute() || die "ERRO na consulta ao BD.";

	($host, $community_ro) = $sth->fetchrow_array;
	$sth->finish;
	$dbh->disconnect;
	if ( !$host || $host eq ''  ){
		print "\n\tERRO: Nao foi encontrada configuracao de acesso SNMP necessaria para \'$equipamento\'.\n";
		$self->{ERROS}++;
		return 0;
	}
	$self->{host}=$host;
	$self->{community} = $community_ro;
	return 1;
}

#===  FUNCTION  ================================================================
#         NAME:  inicio_acesso_snmp
#      PURPOSE:  iniciar uma conexao snmp com as configuracoes do host
#      RETURNS:  objeto NET::SNMP com conexao ativa
#===============================================================================
sub inicio_acesso_snmp(){
	my $self = shift();
	# VARIAVEIS CONFIGURACAO SNMP
	my %SNMP = (
		host       => $self->{host},
		timeout    => $self->{timeout},
		version    => $self->{version},
		community  => $self->{community},
		port       => $self->{port}
		);
	my ($snmp_session,$error) = Net::SNMP->session(
                        -hostname  => $SNMP{host},
                        -version   => $SNMP{version},
                        -timeout   => $SNMP{timeout},
                        -community => $SNMP{community},
                        -port      => $SNMP{port}
                        );  
	if (!defined($snmp_session)) {
        print "ERRO: $error.\n";
		$self->{ERROS}++;
		return 0;
	}   

	$self->{snmp_session} = $snmp_session;
	return 1;
}

#===  FUNCTION  ================================================================
#         NAME:  snmp_get_value
#      PURPOSE:  fazer get snmp
#      RETURNS:  valor de um get snmp
#===============================================================================
sub snmp_get_value{
	my $self = shift();
	my $result = $self->{snmp_session}->get_request(-varbindlist => [$_[0]]);

	if (!defined($result)) {
		print "ERROR: ".$self->{snmp_session}->error."\n";
		$self->{ERROS}++;
		return 0;
	}   
	else{ return $result->{$_[0]}; }
}

#===  FUNCTION  ================================================================
#         NAME:  snmp_get_hash
#      PURPOSE:  obter valores de varios gets snmp
#      RETURNS:  hash com resultados dos gets
#===============================================================================
sub snmp_get_hash{
	my $self = shift();
	my $result = $self->{snmp_session}->get_request(-varbindlist => \@{$_[0]});
	#return $get->{@{$_[0]}[0]};
	if (!defined($result)) {
		print "ERROR: ".$self->{snmp_session}->error."\n";
		$self->{ERROS}++;
		return 0;
	}
	else { return $result; }
}

#===  FUNCTION  ================================================================
#         NAME:  snmp_walk_table
#      PURPOSE:  obter valores de oids snmp a partir de uma oid base
#      RETURNS:  hash com resultados dos gets
#===============================================================================
sub snmp_walk_table{
	my $self = shift();
	my $result = $self->{snmp_session}->get_table(-baseoid => $_[0]);
	#return $get->{@{$_[0]}[0]};
	if (!defined($result)) {
		print "ERROR: ".$self->{snmp_session}->error."\n";
		$self->{ERROS}++;
		return 0;
	}
	else { return $result; }
}

#===  FUNCTION  ================================================================
#         NAME:  snmp_walk
#      PURPOSE:  obter valores snmp a partir de uma oid base
#      RETURNS:  hash com resultados dos gets
#===============================================================================
sub snmp_walk{
	my $self = shift();
	my $result = $self->{snmp_session}->get_entries(-columns => [$_[0]]);
	#return $get->{@{$_[0]}[0]};
	if (!defined($result)) {
		print "ERROR: ".$self->{snmp_session}->error."\n" if ( $self->{snmp_session}->error ne 'Requested entries are empty or do not exist');
		$self->{ERROS}++;
		return 0;
	}
	else { return $result; }
}


#===  FUNCTION  ================================================================
#         NAME:  snmp_set_value
#      PURPOSE:  fazer set snmp
#      RETURNS:  valor de um get snmp
#===============================================================================
sub snmp_set_value{
	my $self = shift();
	my $result = $self->{snmp_session}->set_request(-varbindlist => \@{$_[0]});
	if (!defined($result)) {
		print "ERROR: ".$self->{snmp_session}->error."\n";
		$self->{ERROS}++;
		return 0;
	}
	return 1;
}

#===  FUNCTION  ================================================================
#         NAME:  snmp_set
#      PURPOSE:  setar uma variavel ou conjunto de variaveis snmp
#      RETURNS:  nada
#===============================================================================
sub snmp_set{
	my $self = shift();
	my $get = $self->{snmp_session}->get_request(-varbindlist => [$_[0]]);
	return $get->{$_[0]};
}

#===  FUNCTION  ================================================================
#         NAME:  snmp_set_hex
#      PURPOSE:  setar uma variavel em hexadecimal ou conjunto de variaveis snmp
#      RETURNS:  nada
#===============================================================================
sub snmp_set_hex{
	my $self = shift();
	my $oid = shift();
	my $string = shift();
	
	my $full_path = IPC::Cmd::can_run('snmpset') or die 'ERRO: snmpset nao encontrado!';
	my $cmd = "$full_path -m \"\" -$self->{version} -c $self->{community} ".$self->{host}." $oid x $string";
	my ( $success, $error_code, $full_buf, $stdout_buf, $stderr_buf ) = IPC::Cmd::run( command => $cmd, verbose => 0 );
	
	if ($success != 1){
		print "ERRO: @$stderr_buf", 1;
		return 0;
	}
	return 1;
}

#===  FUNCTION  ================================================================
#         NAME:  snmp_set_tipo
#      PURPOSE:  setar uma variavel em hexadecimal ou conjunto de variaveis snmp
#      RETURNS:  nada
#===============================================================================
sub snmp_set_tipo{
	my $self = shift();
	my $oid = shift();
	my $tipo = shift();
	my $valor = shift();
	
	
	my $full_path = IPC::Cmd::can_run('snmpset') or die 'ERRO: snmpset nao encontrado!';
	my $cmd = "$full_path -m \"\" -$self->{version} -c $self->{community} ".$self->{host}." $oid $tipo $valor";
print "$cmd\n";
	my ( $success, $error_code, $full_buf, $stdout_buf, $stderr_buf ) = IPC::Cmd::run( command => $cmd, verbose => 0 );
	
	if ($success != 1){
		print "ERRO: @$stderr_buf", 1;
		return 0;
	}
	return 1;
}


#===  FUNCTION  ================================================================
#         NAME:  fim_acesso_snmp
#      PURPOSE:  fechar uma conexao snmp
#      RETURNS:  nada
#===============================================================================
sub fim_acesso_snmp() {
	my $self = shift();
	$self->{snmp_session}->close;
}

1;
__END__
