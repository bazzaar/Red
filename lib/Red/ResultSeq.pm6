use Red::AST;
use Red::Column;
use Red::AST::Next;
use Red::AST::Case;
use Red::AST::Empty;
use Red::AST::Value;
use Red::AST::Delete;
use Red::Attr::Column;
use Red::AST::Infixes;
use Red::AST::Chained;
use Red::AST::Function;
use Red::ResultAssociative;
use Red::ResultSeq::Iterator;
unit role Red::ResultSeq[Mu $of = Any] does Sequence;

sub create-resultseq($rs-class-name, Mu \type) is export is raw {
    use Red::DefaultResultSeq;
    my $rs-class := Metamodel::ClassHOW.new_type: :name($rs-class-name);
    $rs-class.^add_parent: Red::DefaultResultSeq;
    $rs-class.^add_role: Red::ResultSeq[type];
    $rs-class.^add_role: Iterable;
    $rs-class.^compose;
    $rs-class
}

method of { $of }
#method is-lazy { True }
method cache {
    List.from-iterator: self.iterator
}

has Red::AST::Chained $.chain handles <filter limit post order group table-list> .= new;

method iterator {
    Red::ResultSeq::Iterator.new: :of($.of), :$.filter, :$.limit, :&.post, :@.order, :@.table-list, :@.group
}

method Seq {
    Seq.new: self.iterator
}

method do-it(*%pars) {
    self.clone(|%pars).Seq
}

#multi method grep(::?CLASS: &filter) { nextwith :filter( filter self.of.^alias: "me" ) }
multi method where(::?CLASS:U: Red::AST:U $filter) { self.WHAT  }
multi method where(::?CLASS:D: Red::AST:U $filter) { self.clone }
multi method where(::?CLASS:U: Red::AST:D $filter) { self.new: :chain($!chain.clone: :$filter) }
multi method where(::?CLASS:D: Red::AST:D $filter) {
    self.clone: :chain($!chain.clone: :filter(($.filter, $filter).grep({ .defined }).reduce: { Red::AST::AND.new: $^a, $^b }))
}

method transform-item(*%data) {
    self.of.bless: |%data
}

method grep(&filter)        { self.where: filter self.of }
method first(&filter)       { self.grep(&filter).head }

#multi treat-map($seq, $filter, Red::Model     $_, &filter, Bool :$flat                 ) { .^where: $filter }
#multi treat-map($seq, $filter,                $_, &filter, Bool :$flat                 ) { $seq.do-it.map: &filter }
#multi treat-map($seq, $filter, Red::ResultSeq $_, &filter, Bool :$flat! where * == True) { $_ }
#multi treat-map($seq, $filter, Red::Column    $_, &filter, Bool :$flat                 ) {
#}

sub hash-to-cond(%val) {
    my Red::AST $ast;
    for %val.kv -> $cond is copy, Bool $so {
        $cond = $so ?? Red::AST::So.new($cond) !! Red::AST::Not.new($cond);
        with $ast {
            $ast = Red::AST::AND.new: $ast, $cond
        } else {
            $ast = $cond
        }
    }
    $ast
}

sub what-does-it-do(&func, \type) {
    my Bool $try-again;
    my $pair;
    my $ret;
    my @*POSS;
    my %poss := :{};
    my %*VALS := :{};
    repeat {
        $try-again = False;
        {
            $ret = func type;
            %poss{ hash-to-cond %*VALS } = do given $ret {
                when Empty {
                    Red::AST::Empty.new
                }
                default {
                    $_
                }
            }

            CATCH {
                when CX::Red::Bool { # needed until we can create real custom CX
                    $try-again = so @*POSS;
                    .resume
                }
            }
            CONTROL {
                when CX::Red::Bool { # Will work when we can create real custom CX
                    $try-again = so @*POSS;
                    .resume
                }
                when CX::Next {
                    %poss{ hash-to-cond %*VALS } = Red::AST::Next.new;
                }
            }
        }
    } while $try-again;
    %poss.values.grep(none(Red::AST::Next, Red::AST::Empty)).head, %poss;
}

multi method create-map($_, &filter)        { self.do-it.map: &filter }
multi method create-map(Red::Model  $_, &?) { .^where: $.filter }
multi method create-map(Red::AST    $_, &?) {
    require ::("MetamodelX::Red::Model");
    my \Meta  = ::("MetamodelX::Red::Model").WHAT;
    my \model = Meta.new.new_type;
    my $attr  = Attribute.new: :name<$!data>, :package(model), :type(.returns), :has_accessor, :build(.returns);
    my $col   = Red::Column.new: :name-alias<data>, :attr-name<data>, :type(.returns.^name), :$attr, :class(model), :computation($_);
    $attr does Red::Attr::Column($col);
    model.^add_attribute: $attr;
    model.^add_method: "no-table", my method no-table { True }
    model.^compose;
    model.^add-column: $attr;
    self.clone(
        :chain($!chain.clone:
            :post({ .data }),
            :$.filter,
            :table-list[(|@.table-list, self.of).unique],
            |%_
        )
    ) but role :: { method of { model } }
}
multi method create-map(Red::Column $_, &?) {
    my \Meta  = .class.HOW.WHAT;
    my \model = Meta.new.new_type;
    my $attr  = Attribute.new: :name<$!data>, :package(model), :type(.attr.type), :has_accessor, :build(.attr.type);
    my $col   = .attr.column.clone: :name-alias<data>, :attr-name<data>;
    $attr does Red::Attr::Column($col);
    model.^add_attribute: $attr;
    model.^add_method: "no-table", my method no-table { True }
    model.^compose;
    model.^add-column: $attr;
    self.clone(
        :chain($!chain.clone:
            :post({ .data }),
            :$.filter,
            :table-list[(|@.table-list, self.of).unique],
            |%_
        )
    ) but role :: { method of { model } }
}

method map(&filter) {
    my @ret  := what-does-it-do(&filter, self.of);
    my %when := @ret.tail;
    my $ret   = @ret.head;
    my @next  = %when.kv.map(-> $k, $v { next unless $v ~~ Red::AST::Next | Red::AST::Empty;  $k });
    do if @next {
        self.where(Red::AST::Not.new: @next.reduce(-> $agg, $n { Red::AST::OR.new: $agg, $n })).map: { $ret }
    } elsif %when {
        self.create-map: Red::AST::Case.new(:%when), &filter
    } else {
        self.create-map: $ret, &filter
    }
}
#method flatmap(&filter) {
#    treat-map :flat, $.filter, filter(self.of), &filter
#}

method sort(&order) {
    my @order = order self.of;
    self.clone: :chain($!chain.clone: :@order)
}

method pick(Whatever) {
    self.clone: :chain($!chain.clone: :order[Red::AST::Function.new: :func<random>])
}

method classify(&func, :&as = { $_ }) {
    my $key   = func self.of;
    my $value = as   self.of;
    #self.clone(:group(func self.of)) but role :: { method of { Associative[$value.WHAT, Str] } }
    Red::ResultAssociative[$value, $key].new: :$.filter, :rs(self)
}

multi method head {
    self.do-it(:1limit).head
}

multi method head(UInt:D $num) {
    self.do-it(:limit(min $num, $.limit)).head: $num
}

method elems {
    self.create-map: Red::AST::Function.new: :func<count>, :args[ast-value *]
}

method new-object(::?CLASS:D: *%pars) {
    my %data = $.filter.should-set;
    my \obj = self.of.bless;#: |%pars, |%data;
    for %(|%pars, |%data).kv -> $key, $val {
        obj.^set-attr: $key, $val
    }
    obj
}

method create(::?CLASS:D: *%pars) {
    $.of.^create: |%pars, |(.should-set with $.filter);
}

method delete(::?CLASS:D:) {
    $*RED-DB.execute: Red::AST::Delete.new: $.of, $.filter
}
