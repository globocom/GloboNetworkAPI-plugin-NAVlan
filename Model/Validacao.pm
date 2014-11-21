#===============================================================================
#
#         FILE:  Validacao.pm
#          RCS:  $ Header $
#
#  DESCRIPTION:  Contem funcoes utilizadas na validacao do NaVLAN 
#
#        NOTES:  ---
#       AUTHOR:  Douglas Magno (DM), <dmagno@corp.globo.com>
#      COMPANY:  Globo.com - Datacenter - Telecom
#      VERSION:  1.0
#      CREATED:  30-06-2008 20:52:30 BRT
#     REVISION:  $ Revision $
#===============================================================================
package Model::Validacao; 

use strict;
require Exporter;
use vars qw($VERSION @ISA @EXPORT);
use warnings;
use English;

@ISA = qw(Exporter);
@EXPORT = qw( 
    valida_IP
    valida_Network
    valida_vlanid
    valida_MaskCIDR
    valida_MaskCIDR_VLAN
    valida_NetParaAmbiente
);


$VERSION = '1.0';

use Regexp::Common; 
use Regexp::Common qw( net );
use NetAddr::IP::Lite qw( :aton );
#use NetAddr::IP::Util qw( isIPv4 );

use Model::Conf  qw( %campos %amb %amb_conf $BIN_IPCALC );





# valida_IP -------------------------------------------------------------------- 
# Valida se sintaxe do IP no formato decimal esta certo
# Retorna Verdadeiro se Sim, Falso caso contrario 
sub valida_IP($){
    my $ip = shift       or die;
    return 0 if not $ip =~ /^$RE{net}{IPv4}$/;
    return 1;
}




# valida_NetMask --------------------------------------------------------------- 
# Valida se IP de Subrede eh uma subrede com a mascara CIDR utilizada 
# Retorna Verdadeiro se Sim, Falso caso contrario 
# Recebe: 
#   REDE
#   MASCARA 
#   USO = 'VLAN' se for para validar rede que sera utilizada para criar VLAN
#          senao undef
sub valida_Network($$$) {
    my ($net, $mask, $uso) = @_       or die;
    my $ip;

    $uso ||= 0;

    return 0 unless valida_IP($net);

    if ($uso eq 'VLAN') {
        return 0 unless valida_MaskCIDR_VLAN($mask);
    } 
    else {
        return 0 unless valida_MaskCIDR($mask);
    }


    eval { 
         $ip = new NetAddr::IP::Lite($net,$mask);
    };
    return 0 if $EVAL_ERROR;

    return ($ip->addr eq $ip->network()->addr);
} 




# valida_vlanid ----------------------------------------------------------------- 
# Valida Se Numero de ID para VLAN eh valido 
# Retorna Verdadeiro se Sim, Falso caso contrario 
sub valida_vlanid($) {
    my $id = shift          or die;
    return 0 unless $id =~ qr/^$RE{num}{int}$/;
    return ($id >= 2 && $id <= 1001) or ($id >= 1006 && $id <= 4094 );
}




# valida_MaskCIDR para VLAN ---------------------------------------------------- 
# Range Valido de tamanho de mascara para ser utilizado na criacao de VLAN
sub valida_MaskCIDR_VLAN($) {
    my $mask = shift;
    return undef  unless valida_MaskCIDR($mask); 
    return $mask <= 30 && $mask >= 2 ;
}


# valida_MaskCIDR -------------------------------------------------------------- 
# Valida Tamanho da Mascara CIDR 
# Retorna Verdadeiro se Sim, Falso caso contrario 
sub valida_MaskCIDR($) {
    my $mask = shift;
    return undef  unless $mask =~ /^\d+$/;
    return $mask <= 32 && $mask >= 1 ;
}


# Dado SUBREDE/MASCARA validos retorna se subrede esta dentro do range
# alocado para o ambiente
# $amb_range no formato IP.IP.IP.IP/CIDR
sub valida_NetParaAmbiente {
    my ($net, $mask, $amb_range) = @_;
    my ($subnet, $range);

    return 0 unless valida_Network($net,$mask, 'VLAN');

    eval {
        $subnet = new NetAddr::IP::Lite($net, $mask);
        $range  = new NetAddr::IP::Lite($amb_range);
    };
    return undef if $EVAL_ERROR; 

    return $subnet->within( $range );
}



