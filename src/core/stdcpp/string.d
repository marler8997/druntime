module core.stdcpp.string;

import core.stdcpp.memory : allocator;

extern(C++, std):

struct char_traits
{
}

struct basic_string(CharT, Traits = char_traits!CharT, Allocator = allocator!CharT)
{
    bool empty() const;

    ref CharT front();
    ref const(CharT) front() const;

    // TODO: define reference/const_reference
    //reference at(Traits.size_type pos);
    //const_reference at(size_type pos) const;
}