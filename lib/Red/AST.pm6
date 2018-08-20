enum Red::Op << merge eq ne lt gt le ge like ilike not cast and or >>;
unit class Red::AST;

has Red::Op $.op;
has List    $.args;
has List    $.bind;
has Set     $.tables = ∅;

submethod TWEAK(|) {
    for $!args<> // [] {
        if .^can: "class" {
            $!tables ∪= .class
        }
    }
    for $!bind<> // [] {
        if .^can: "class" {
            $!tables ∪= .class
        }
    }
}

multi method WHICH(::?CLASS:D:) { "{self.^name}|$!op|{$!args>>.WHICH}|{$!bind>>.WHICH}" }

multi method WHICH(::?CLASS:U:) { "{self.^name}" }

multi method perl(::?CLASS:U:) { "{self.^name}" }

multi method perl(::?CLASS:D:) { "{self.^name}.new(:op({$!op}), :args({$!args.perl}), :bind({$!bind.perl}))" }

multi method merge(::?CLASS:U: ::?CLASS:D $filter) { $filter }

multi method merge(::?CLASS:D: ::?CLASS:D $filter) {
    ::?CLASS.new: :op(merge), :args(self, $filter)
}

multi substitute(%alias, $item) { $item }

multi substitute(%alias, Red::AST $item) {
    $item.substitute: %alias
}

multi substitute(%alias, $item where { .^can("attr") and $item.attr.column.class ~~ any(%alias.keys) }) {
    $item.clone: attr => $item.attr.clone: column => $item.attr.column.clone: class => %alias{ $item.attr.column.class }
}

multi substitute(%alias, $item where { .^can("class") and $item.class ~~ any(%alias.keys) }) {
    $item.clone: :class(%alias{ $item.class })
}

method substitute(%alias) {
    #my &subst = &substitute.assuming: %alias;
    #Red::AST.new: :$!op, :args($!args>>.&subst), :bind($!bind>>.&subst)
    self
}
