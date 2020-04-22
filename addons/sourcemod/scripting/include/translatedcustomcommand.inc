#include <customcommand>

#define MAX_TRANSLATION_SIZE 255

methodmap TranslatedCustomCommand < CustomCommand
{
    public TranslatedCustomCommand()
    {
        return view_as<TranslatedCustomCommand>(new CustomCommand());
    }

    public void GetTranslation(char[] buffer, int size)
    {
        this.GetString("translation", buffer, size);
    }

    public void SetTranslation(const char[] trans)
    {
        this.SetString("translation", trans);
    }
};