using System.Windows.Controls;
using PmToolsGui.ViewModels;

namespace PmToolsGui.Views;

public partial class DownloadsView : UserControl
{
    public DownloadsView(DownloadsViewModel viewModel)
    {
        InitializeComponent();
        DataContext = viewModel;
    }
}
