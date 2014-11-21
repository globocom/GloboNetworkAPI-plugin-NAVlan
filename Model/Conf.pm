#===============================================================================
#
#         FILE:  Conf.pm
#          RCS:  $ Header $
#
#  DESCRIPTION:  Contem definicoes comuns para scripts do projeto NavLan
#                como nome de ambientes, campos do formulario etc
#
#        NOTES:  ---
#       AUTHOR:  Douglas Magno (DM), <dmagno@corp.globo.com>
#      COMPANY:  Globo.com - Datacenter - Telecom
#      VERSION:  1.0
#      CREATED:  30-06-2008 20:52:30 BRT
#     REVISION:  $ Revision $
#      RCS LOG:  $ Log $
#===============================================================================
package Model::Conf; 

use strict;
require Exporter;
use vars qw($VERSION @ISA @EXPORT);
use warnings;

@ISA = qw(Exporter);
@EXPORT = qw( %campos %amb %amb_ids %amb_conf $TMPL_DIR $TMPL_VLAN $BIN_IPCALC );
$VERSION = '1.0';




#--------------------------------------------------------------------------------
# Configuracoes GERAIS 

# Localizacao dos Templates
our $TMPL_DIR    = 'Model/templates';
our $TMPL_VLAN   = 'prod_fe_portal.tt';


# Binario ipcalc
our $BIN_IPCALC = 'Model/bin/ipcalc';


#--------------------------------------------------------------------------------
# Campos FORMULARIO
our %campos = (
    'vlan_id'       => 'ID da VLAN',
    'vlan_mask'     => 'M&aacute;scara',
    'vlan_name'     => 'Nome', 
    'vlan_net'     => 'Rede', 
    'vlan_ambiente' => 'Ambiente', 
);



#--------------------------------------------------------------------------------
#Definicao de Ambientes

# Definicao de ambientes de acordo com BD Telecom
#TODO Select this automatically from the DB
our %amb_ids = (
    1 => 'environment_name_identifier',
    2 => 'environment_name_identifier2'
);


# Nomes ambientes
#TODO Remove dead code
our %amb = (
    environment_name_identifier     => 'Long description for environment name 01',
    environment_name_identifier2  => 'Long description for environment name 02'
);

# Configuracoes de Equipamentos por Ambiente
# L3         : Equipamentos que fazem o roteamento em Layer 3
# L2         : Equipamentos que fazem a comutacao em Layer 2
# vtp_master : Equipamento que eh o Master VTP no ambiente
# range       : Range(s) de IP's alocado para ao ambiente
#              No formato  IP.IP.IP.IP/TAMANHO_MASCARA_SUBREDE
# tmpl       : Nomes dos arquivos de Template associados a esse ambiente

our %amb_conf;
#Here should be defined the equipments that are supposed to be cofigured for the environment
#TODO change the L3 by the router equipment flag in the DB
#TODO Import the other data to DB and remove this config file
$amb_conf{environment_name_identifier}{L3}         = [ qw( equipment_name01 equipment_name02 ) ];
$amb_conf{environment_name_identifier}{L2}         = [ qw( not used ) ];
$amb_conf{environment_name_identifier}{range}      = 'not used';
$amb_conf{environment_name_identifier}{sufixo}     = 'not used';
$amb_conf{environment_name_identifier}{tmpl}  = [(
            {titulo => 'equipment_name01',
             file   => 'example_template01.tt',
             file_remove => 'example_template01_delete.tt'},
            {titulo => 'equipment_name02',
             file   => 'example_template02.tt',
             file_remove => 'example_template02_delete.tt'},
        )]; 


#--------------------------------------------------------------------------------




1;
__END__
