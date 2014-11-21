#===============================================================================
#
#         FILE:  Codeman.pm
#          RCS:  $ Header $
#
#  DESCRIPTION:  Inclui parte da Logica para Geracao de Codigo
#                Basciamente coordenada a chamado aos arquivos de template
#               
#        NOTES:  ---
#       AUTHOR:  Douglas Magno (DM), <dmagno@corp.globo.com>
#      COMPANY:  Globo.com - Datacenter - Telecom
#      VERSION:  1.0
#      CREATED:  01-07-2008 16:00:15 BRT
#     REVISION:  $ Revision $
#      RCS LOG:  $ Log $
#===============================================================================

package Controller::Codeman;

use strict;
use warnings;
use English;
use vars qw($VERSION @ISA @EXPORT %EXPORT_TAGS);
use Template;
use Data::Dumper;
use NetAddr::IP::Lite qw( :aton );

# Numero Maximo de IP's Permitido na subrede
my $SUBNET_MAX_IP = 8192;


use Model::Conf qw( %campos %amb %amb_conf $TMPL_DIR $TMPL_VLAN );
our (%campos, %amb, $TMPL_DIR, $TMPL_VLAN);

$VERSION     = 0.01;
@ISA         = qw(Exporter);
@EXPORT      = qw( gerarCodigos %campos );





#--------------------------------------------------------------------------------
# Gera codigo que dever ser aplicado aos equipamentos 

# Retorna um Array com Hashes Contendo Titulo e Conteudo Gerado

sub gerarCodigos($) {
    my $self = shift;
    $_       = shift; 
    my %var = %{ $_ };

    my $ambiente = $var{vlan_ambiente};

    my $codigo;

    my @retorno;

    # Objeto para processamento dos Templates
    my $tt = Template->new( { 
                                INCLUDE_PATH => $TMPL_DIR ,
                                RELATIVE     => 1,
                            } );

    # Gera variaveis adicionais que o template necessita para ser gerado 
    %var = &geraVariaveisParaTemplate(\%var);

    # Nome do arquivo de template
    #my $tmpl_file = $var{vlan_ambiente} . '.tt';
    #$tt->process("./$TMPL_DIR/$tmpl_file", \%var)     
    #or die ">> Falha durante processamento do template '$tmpl_file':\n" .  $tt->error;
    # WIKI
    #$tt->process("./$TMPL_DIR/wiki_vlan.tt", \%var)     
    #or die ">> Falha durante processamento do template '$tmpl_file':\n" .  $tt->error;


    # Gera os Codigos para Cada um dos Templates associados ao Ambiente
    foreach my $tmpl ( @{ $var{amb}{tmpl} } ) {
        my $tmpl_file   = $tmpl->{file}         or die;
        my $tmpl_file_remove   = $tmpl->{file_remove}         or die;
        my $tmpl_titulo = $tmpl->{titulo}       or die;

        if (not -e "$TMPL_DIR/$tmpl_file") {
            print ">> Este ambiente pode ainda nao estar completamente implementado.
            >> Nao foi encontrado arquivo de template '$tmpl_file' para o ambiente '$amb{$var{vlan_ambiente}}'.";
            next ;
        }
        if (not -e "$TMPL_DIR/$tmpl_file_remove") {
            print ">> Este ambiente pode ainda nao estar completamente implementado.
            >> Nao foi encontrado arquivo de template '$tmpl_file_remove' para o ambiente '$amb{$var{vlan_ambiente}}'.";
            next ;
        }

        my %r;
        $r{titulo}  = $tmpl_titulo;
        $r{file}    = $tmpl_file;
        $r{file_remove} = $tmpl_file_remove;
        
        $tt->process("./$TMPL_DIR/$tmpl_file", \%var, \$r{conteudo} )     
            or die "\n>> Falha durante processamento do template '$tmpl_file':\n" .  $tt->error;

        $tt->process("./$TMPL_DIR/$tmpl_file_remove", \%var, \$r{conteudo_remove} )     
            or die "\n>> Falha durante processamento do template '$tmpl_file_remove':\n" .  $tt->error;

        push @retorno, \%r;
    }

    return @retorno;

}





#--------------------------------------------------------------------------------
# Gera variaveis adicionais que o Template podera precisar

sub geraVariaveisParaTemplate($) {
    $_       = shift; 
    my %var = %{ $_ };
    $var{tmpl_dir} = $TMPL_DIR;


    my $ip = new NetAddr::IP::Lite($var{vlan_net}, $var{vlan_mask});

    # Gerando NETNUMBER = Número de rede da vlan, sem o host (parte fixa, ex 172.16.61)
    $var{vlan_netnumber} = $var{vlan_net}; 

    # TODO: Utilizar modulo cpan para calculor correto
    $var{vlan_netnumber} =~ s/\.\d+$//;     # Retirando ultimo octeto

	#Nao e mais utilizadoe nao pode ser usado com IPv6.
    #$var{vlan_wildmask}  = &netmask_to_wildmask($ip->mask);

    $var{vlan_mask_num} = $var{vlan_mask};  # Comprimento da Mascara
    $var{vlan_mask}     = $ip->mask();      # Mascara em formato A.A.A.A
    $var{vlan_bloco}     = $ip->masklen();      # Mascara em formato CIDR /numero de bits

    # Retirando possiveis caracteres invalidos do nome da VLAN
    #$var{vlan_name} = removeAcentuacao($var{vlan_name});
    $var{vlan_name} =~ s/\W/_/g;
    #$var{vlan_name} =~ s/__+/_/g;

    # Nome por Extenso do ambiente 

    my $vlan_ambiente = $var{vlan_ambiente};
    # Nome legivel do ambiente
    if( not $var{vlan_amb_nome} ){
    	$var{vlan_amb_nome} = $amb{$vlan_ambiente};
    }

    # Copia dos valores da configuracao do ambiente, para facilitar acesso a partir do template
    foreach (keys %{ $amb_conf{$vlan_ambiente} } ) {
        $var{amb}{$_} = $amb_conf{ $vlan_ambiente }{$_};
    }

    # Nome dos Equipamentos que fazem L3 na VLAN
    $var{vlan_eqpto_l3} = uc( join('/', @{$amb_conf{ $var{vlan_ambiente} }{L3} }) );

    # Gerando Enderecos Usuais de Rede
    my ($subnet);
    eval {
        $subnet = new NetAddr::IP::Lite( $var{vlan_net} , $var{vlan_mask} );
    };
    die "Endereco de Rede Mal Formado" if $EVAL_ERROR; 

    $var{vlan_net_broadcast} = $subnet->broadcast()->addr();

    # Ultimo Endereco IP Usavel = Broadcast - 1
    $var{vlan_net_ultimo}      = $subnet->last()->addr();

    # Ultimo Endereco IP Usavel = Broadcast - 2
    $var{vlan_net_penultimo}   = ($subnet->last() - 1)->addr();

    # Primeiro Endereco IP Usavel
    $var{vlan_net_primeiro}    = $subnet->first()->addr();

    # Segundo Endereco IP Usavel
    $var{vlan_net_segundo}    = ($subnet->first() + 1)->addr();


    # Gera Todos os IP's usaveis dentro da subrede
    my @ips_usaveis;
    my $i = new NetAddr::IP::Lite( $subnet );
    my $count = 0;
    while( $i <= $subnet->last() - 1 ) {
        $i = $i + 1;
        push @ips_usaveis, $i->addr(); 
        if (++$count == $SUBNET_MAX_IP) {
            #TODO... colocar este tratamento em outro lugar melhor
            push @ips_usaveis, "Gerado ate o maximo de $SUBNET_MAX_IP IP's";
            last;
        } 
    }
    $var{vlan_ips_usaveis} = [@ips_usaveis];

    return %var;
}






# TODO Colocar em modulo a parte
#--------------------------------------------------------------------------------
# Recebe uma mascara de rede no formato decimal e retorna a wildmask tambem
# no formato decimal
sub netmask_to_wildmask($) {
    my $wildmask;
    map{ $wildmask .= (255 - $_) . '.' } split('\.', $_[0]);
    $wildmask =~ s/\.$//;
    return $wildmask;
}


#--------------------------------------------------------------------------------
# Valida dados entrados pelo formulario
sub validaDadosVlan($) {

}


sub removeAcentuacao($) {
    my $input = shift   or die;
    $input =~ tr/ÀÁÃÂÉÊÍÓÕÔÚÜÇàáãâéêíóõôúüç/AAAAEEIOOOUUCaaaaeeiooouuc/;
    return $input;
}









1;
__END__


# TODO
# Retornar codigo gerados em Hash contendo equipamento alvo e respectivo codigo
# Process do TT returnar para variavel
# Calculo correto no netnumber

# Exportar para template nome hash de nome das vlans
