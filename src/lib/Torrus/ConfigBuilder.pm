#  Copyright (C) 2002  Stanislav Sinyagin
#
#  This program is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 2 of the License, or
#  (at your option) any later version.
#
#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  You should have received a copy of the GNU General Public License
#  along with this program; if not, write to the Free Software
#  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA 02111-1307, USA.

# Stanislav Sinyagin <ssinyagin@k-open.com>

# XML configuration builder

package Torrus::ConfigBuilder;

use strict;
use warnings;

use XML::LibXML;
use IO::File;

use Torrus::Log;


# TMPLNAME => {name => NAME, source => XMLFILE}
our %templateRegistry;

# SEQUENCE => {TMPLNAME => {name => NAME, source => XMLFILE}}
our %pluginTemplateRegistry;


sub new
{
    my $self = {};
    my $class = shift;
    bless $self, $class;

    my $doc = XML::LibXML->createDocument( "1.0", "UTF-8" );
    my $root = $doc->createElement('configuration');
    $doc->setDocumentElement( $root );
    $self->{'doc'} = $doc;
    $self->{'docroot'} = $root;

    $root->appendChild($doc->createComment('DO NOT EDIT THIS FILE'));

    my $dsnode = $doc->createElement('datasources');
    $self->{'docroot'}->appendChild( $dsnode );
    $self->{'datasources'} = $dsnode;

    $self->{'required_templates'} = {};

    $self->{'statistics'} = {};

    $self->{'registry_overlays'} = [];
    
    return $self;
}


sub setRegistryOverlays
{
    my $self = shift;
    
    $self->{'registry_overlays'} = [];
    push( @{$self->{'registry_overlays'}}, @_ );
    return;
}


sub lookupRegistry
{
    my $self = shift;
    my $template = shift;

    my $ret = undef;

    foreach my $regOverlay ( @{$self->{'registry_overlays'}} )
    {
        if( defined( $regOverlay->{$template} ) )
        {
            $ret = $regOverlay->{$template};
        }
    }

    if( not defined($ret) )
    {
        foreach my $sequence (sort {$a <=> $b} keys %pluginTemplateRegistry)
        {
            if( defined( $pluginTemplateRegistry{$sequence}{$template} ) )
            {
                $ret = $pluginTemplateRegistry{$sequence}{$template};
                last;
            }
        }
    }
        
    if( not defined($ret) and
        defined( $templateRegistry{$template} ) )
    {
        $ret = $templateRegistry{$template};
    }
    
    if( not defined($ret) )
    {
        if( scalar(keys %templateRegistry) > 0 )
        {
            Warn('Template ' . $template .
                 ' is not listed in ConfigBuilder template registry');
        }
    }

    return $ret;
}
    



sub addCreatorInfo
{
    my $self = shift;
    my $creatorInfo = shift;

    my $creatorNode = $self->{'doc'}->createElement('creator-info');
    $creatorNode->appendText( $creatorInfo );
    $self->{'docroot'}->insertBefore( $creatorNode, $self->{'datasources'} );
    return;
}


sub addRequiredFiles
{
    my $self = shift;

    foreach my $file ( $self->requiredFiles() )
    {
        $self->addFileInclusion( $file );
    }
    return;
}


sub addFileInclusion
{
    my $self = shift;
    my $file = shift;

    my $node = $self->{'doc'}->createElement('include');
    $node->setAttribute( 'filename', $file );
    $self->{'docroot'}->insertBefore( $node, $self->{'datasources'} );
    return;
}


sub startDefinitions
{
    my $self = shift;

    my $node = $self->{'doc'}->createElement('definitions');
    $self->{'docroot'}->insertBefore( $node, $self->{'datasources'} );
    return $node;
}


sub addDefinition
{
    my $self = shift;
    my $definitionsNode = shift;;
    my $name = shift;
    my $value = shift;

    my $node = $self->{'doc'}->createElement('def');
    $node->setAttribute( 'name', $name );
    $node->setAttribute( 'value', $value );
    $definitionsNode->appendChild( $node );
    return;
}


sub startParamProps
{
    my $self = shift;

    my $node = $self->{'doc'}->createElement('param-properties');
    $self->{'docroot'}->insertBefore( $node, $self->{'datasources'} );
    return $node;
}


sub addParamProp
{
    my $self = shift;
    my $propsNode = shift;;
    my $param = shift;
    my $prop = shift;
    my $value = shift;

    my $node = $self->{'doc'}->createElement('prop');
    $node->setAttribute( 'param', $param );
    $node->setAttribute( 'prop', $prop );
    $node->setAttribute( 'value', $value );
    $propsNode->appendChild( $node );
    return;
}



sub addSubtree
{
    my $self = shift;
    my $parentNode = shift;
    my $subtreeName = shift;
    my $params = shift;      # hash reference with param name-value pairs
    my $templates = shift;   # array reference with template names

    return $self->addChildElement( 0, $parentNode, $subtreeName,
                                   $params, $templates );
}


sub addLeaf
{
    my $self = shift;
    my $parentNode = shift;
    my $leafName = shift;
    my $params = shift;      # hash reference with param name-value pairs
    my $templates = shift;   # array reference with template names

    return $self->addChildElement( 1, $parentNode, $leafName,
                                   $params, $templates );
}


sub addChildElement
{
    my $self = shift;
    my $isLeaf = shift;
    my $parentNode = shift;
    my $childName = shift;
    my $params = shift;
    my $templates = shift;

    my $doc = $self->{'doc'};

    if( not ref( $parentNode ) )
    {
        $parentNode = $self->{'datasources'};
    }

    my $childNode = $doc->createElement( $isLeaf ? 'leaf' : 'subtree' );
    $childNode->setAttribute( 'name', $childName );
    $childNode = $parentNode->appendChild( $childNode );

    if( ref( $templates ) )
    {
        foreach my $tmpl ( sort @{$templates} )
        {
            $self->addTemplateApplication( $childNode, $tmpl );
        }
    }

    $self->addParams( $childNode, $params );

    return $childNode;
}


sub getChildSubtree
{
    my $self = shift;
    my $parentNode = shift;
    my $childName = shift;

    if( not ref( $parentNode ) )
    {
        $parentNode = $self->{'datasources'};
    }
    
    my @subtrees =
        $parentNode->findnodes( 'subtree[@name="' . $childName . '"]' );
    if( not @subtrees )
    {
        Error('Cannot find subtree named ' . $childName);
        return undef;
    }
    return $subtrees[0];
}


# Reconstruct the path to the given subtree or leaf
sub getElementPath
{
    my $self = shift;
    my $node = shift;

    my $path = '';
    if( $node->nodeName() eq 'subtree' )
    {
        $path = '/';
    }

    while( not $node->isSameNode( $self->{'datasources'} ) )
    {
        $path = '/' . $node->getAttribute( 'name' ) . $path;
        $node = $node->parentNode();
    }
    
    return $path;
}


sub getTopSubtree
{
    my $self = shift;
    return $self->{'datasources'};
}


sub addTemplateApplication
{
    my $self = shift;
    my $parentNode = shift;
    my $template = shift;

    if( not ref( $parentNode ) )
    {
        $parentNode = $self->{'datasources'};
    }

    my $found = 0;

    my $reg = $self->lookupRegistry( $template );
    if( defined( $reg ) )
    {
        $self->{'required_templates'}{$template} = 1;
        my $name = $reg->{'name'};
        if( defined( $name ) )
        {
            $template = $name;
        }
    }
    
    my $tmplNode = $self->{'doc'}->createElement( 'apply-template' );
    $tmplNode->setAttribute( 'name', $template );
    $parentNode->appendChild( $tmplNode );
    return;
}


sub addParams
{
    my $self = shift;
    my $parentNode = shift;
    my $params = shift;

    if( ref( $params ) )
    {
        foreach my $paramName ( sort keys %{$params} )
        {
            $self->addParam( $parentNode, $paramName, $params->{$paramName} );
        }
    }
    return;
}


sub addParam
{
    my $self = shift;
    my $parentNode = shift;
    my $param = shift;
    my $value = shift;

    if( not ref( $parentNode ) )
    {
        $parentNode = $self->{'datasources'};
    }

    my $paramNode = $self->{'doc'}->createElement( 'param' );
    $paramNode->setAttribute( 'name', $param );
    $paramNode->setAttribute( 'value', $value );
    $parentNode->appendChild( $paramNode );
    return;
}



sub setVar
{
    my $self = shift;
    my $parentNode = shift;
    my $name = shift;
    my $value = shift;

    my $setvarNode = $self->{'doc'}->createElement( 'setvar' );
    $setvarNode->setAttribute( 'name', $name );
    $setvarNode->setAttribute( 'value', $value );
    $parentNode->appendChild( $setvarNode );
    return;
}
    
    

sub startMonitors
{
    my $self = shift;

    my $node = $self->{'doc'}->createElement('monitors');
    $self->{'docroot'}->appendChild( $node );
    return $node;
}


sub addMonitorAction
{
    my $self = shift;
    my $monitorsNode = shift;;
    my $name = shift;
    my $params = shift;

    my $node = $self->{'doc'}->createElement('action');
    $node->setAttribute( 'name', $name );
    $monitorsNode->appendChild( $node );

    $self->addParams( $node, $params );
    return;
}


sub addMonitor
{
    my $self = shift;
    my $monitorsNode = shift;;
    my $name = shift;
    my $params = shift;

    my $node = $self->{'doc'}->createElement('monitor');
    $node->setAttribute( 'name', $name );
    $monitorsNode->appendChild( $node );

    $self->addParams( $node, $params );
    return;
}


sub startTokensets
{
    my $self = shift;

    my $node = $self->{'doc'}->createElement('token-sets');
    $self->{'docroot'}->appendChild( $node );
    return $node;
}


sub addTokenset
{
    my $self = shift;
    my $tsetsNode = shift;;
    my $name = shift;
    my $params = shift;

    my $node = $self->{'doc'}->createElement('token-set');
    $node->setAttribute( 'name', $name );
    $tsetsNode->appendChild( $node );

    $self->addParams( $node, $params );
    return;
}


sub addStatistics
{
    my $self = shift;

    foreach my $stats ( sort keys %{$self->{'statistics'}} )
    {
        my $node = $self->{'doc'}->createElement('configbuilder-statistics');
        $node->setAttribute( 'category', $stats );
        $node->setAttribute( 'value', $self->{'statistics'}{$stats} );
        $self->{'docroot'}->appendChild( $node );
    }
    return;
}


sub addComment
{
    my $self = shift;
    my $parentNode = shift;
    my $msg = shift;
    
    $parentNode->appendChild($self->{'doc'}->createComment($msg));
    return;
}


sub requiredFiles
{
    my $self = shift;

    my %files;
    foreach my $template ( keys %{$self->{'required_templates'}} )
    {
        my $file;
        my $reg = $self->lookupRegistry( $template );
        if( defined( $reg ) )
        {
            $file = $reg->{'source'};
        }
        
        if( defined( $file ) )
        {
            $files{$file} = 1;
        }
        else
        {
            Error('Source file is not defined for template ' . $template .
                  ' in ConfigBuilder template registry');
        }
    }
    return( sort keys %files );
}



sub toFile
{
    my $self = shift;
    my $filename = shift;

    my $fh = new IO::File('> ' . $filename);
    if( defined( $fh ) )
    {
        my $ok = $self->{'doc'}->toFH( $fh, 2 );
        $fh->close();
        return $ok;
    }
    else
    {
        return undef;
    }
}

1;


# Local Variables:
# mode: perl
# indent-tabs-mode: nil
# perl-indent-level: 4
# End:
