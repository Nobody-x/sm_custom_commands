#define MAX_CUSTOM_COMMAND_NAME 32

methodmap CustomCommand < StringMap
{
    public CustomCommand()
    {
        return view_as<CustomCommand>(new StringMap());
    }

    public void GetName(char[] buffer, int size)
    {
        this.GetString("name", buffer, size);
    }

    public void SetName(const char[] name)
    {
        this.SetString("name", name);
    }
};