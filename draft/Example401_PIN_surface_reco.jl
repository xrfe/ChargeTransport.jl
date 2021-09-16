#=
# 401: 1D GaAs p-i-n diode with surface recombination.
([source code](SOURCE_URL))

Simulating charge transport in a GaAs pin diode. This means
the corresponding PDE problem corresponds to the van Roosbroeck
system of equations, i.e. the unknowns are given by the quasi Fermi 
potentials of electrons and holes φ_n, φ_p and the electric potential ψ.
The simulations are performed out of equilibrium and for the
stationary problem.
=#

module Example401_PIN_surface_reco

using VoronoiFVM               # PDE solver with a FVM spatial discretization
using ChargeTransportInSolids  # drift-diffusion solver
using ExtendableGrids          # grid initializer
using GridVisualize            # grid visualizer
using PyPlot
using DelimitedFiles


# function for initializing the grid for a possble extension to other p-i-n devices.
function initialize_pin_grid(refinementfactor, h_ndoping, h_intrinsic, h_pdoping)
    coord_ndoping    = collect(range(0.0, stop = h_ndoping, length = 3 * refinementfactor))
    coord_intrinsic  = collect(range(h_ndoping, stop = (h_ndoping + h_intrinsic), length = 3 * refinementfactor))
    coord_pdoping    = collect(range((h_ndoping + h_intrinsic), stop = (h_ndoping + h_intrinsic + h_pdoping), length = 3 * refinementfactor))
    coord            = glue(coord_ndoping, coord_intrinsic)
    coord            = glue(coord, coord_pdoping)

    return coord
end


function main(;n = 8, Plotter = PyPlot, plotting = false, verbose = false, test = false, unknown_storage=:sparse)

    ################################################################################
    if test == false
        println("Set up grid and regions")
    end
    ################################################################################

    # region numbers
    regionAcceptor          = 1          # p doped region
    regionIntrinsic         = 2          # intrinsic region
    regionDonor             = 3          # n doped region
    regions                 = [regionAcceptor, regionIntrinsic, regionDonor]
    numberOfRegions         = length(regions)

    # boundary region numbers
    bregionAcceptor         = 1
    bregionDonor            = 2
    bregionJunction1        = 3
    bregionJunction2        = 4
    bregions                = [bregionAcceptor, bregionDonor, bregionJunction1, bregionJunction2]

    # grid
    refinementfactor        = 2^(n-1)
    h_pdoping               = 2 * μm
    h_intrinsic             = 2 * μm
    h_ndoping               = 2 * μm
    coord                   = initialize_pin_grid(refinementfactor,
                                                  h_pdoping,
                                                  h_intrinsic,
                                                  h_ndoping)

    grid                    = simplexgrid(coord)

    # cellmask! for defining the subregions and assigning region number (doping profiles do not intersect)
    cellmask!(grid, [0.0 * μm],                [h_pdoping],                           regionAcceptor)  # p-doped region = 1
    cellmask!(grid, [h_pdoping],               [h_pdoping + h_intrinsic],             regionIntrinsic) # intrinsic region = 2
    cellmask!(grid, [h_pdoping + h_intrinsic], [h_pdoping + h_intrinsic + h_ndoping], regionDonor)     # n-doped region = 3

    # bfacemask! for ``active'' boundary regions, i.e. internal interfaces. On the outer boudary regions, the 
    # conditions will be formulated later
    bfacemask!(grid, [h_pdoping],               [h_pdoping],                           bregionJunction1)  # first  inner interface
    bfacemask!(grid, [h_pdoping + h_intrinsic], [h_pdoping + h_intrinsic],             bregionJunction2)  # second inner interface

    # if plotting
    #     gridplot(grid, Plotter = Plotter, legend=:lt)
    #     Plotter.title("Grid")
    #     Plotter.figure()
    # end

    if test == false
        println("*** done\n")
    end
    ################################################################################
    if test == false
        println("Define physical parameters and model")
    end
    ################################################################################

    # set indices of the quasi Fermi potentials
    iphin              = 1 # electron quasi Fermi potential
    iphip              = 2 # hole quasi Fermi potential
    numberOfCarriers   = 2 

    # physical data
    Ec                 = 1.424                *  eV
    Ev                 = 0.0                  *  eV
    Nc                 = 4.351959895879690e17 / (cm^3)
    Nv                 = 9.139615903601645e18 / (cm^3)
    mun                = 8500.0               * (cm^2) / (V * s)
    mup                = 400.0                * (cm^2) / (V * s)
    εr                 = 12.9                 *  1.0              # relative dielectric permittivity of GAs
    T                  = 300.0                *  K

    # recombination model
    bulk_recombination = bulk_recomb_model_full # use full recombination

    # recombination parameters
    Auger             = 1.0e-29              * cm^6 / s     
    SRH_TrapDensity   = 1.0e10               / cm^3            
    SRH_LifeTime      = 1.0                  * ns             
    Radiative         = 1.0e-10              * cm^3 / s 

    # doping
    dopingFactorNd    = 1.0
    dopingFactorNa    = 0.46
    Nd                = dopingFactorNd * Nc
    Na                = dopingFactorNa * Nv

    # intrinsic concentration (not doping!)
    ni                = sqrt(Nc * Nv) * exp(-(Ec - Ev) / (2 * kB * T)) 

    # contact voltages: we impose an applied voltage only on one boundary.
    # At the other boundary the applied voltage is zero.
    voltageAcceptor   = 1.5                  * V

    if test == false
        println("*** done\n")
    end
    ################################################################################
    if test == false
        println("Define ChargeTransportSystem and fill in information about model")
    end
    ################################################################################

    # initialize ChargeTransportData instance and fill in data
    data                                = ChargeTransportData(grid, numberOfCarriers)

    #### declare here all necessary information concerning the model ###

    # Following variable declares, if we want to solve stationary or transient problem
    data.model_type                     = model_stationary

    # Following choices are possible for F: Boltzmann, FermiDiracOneHalfBednarczyk, FermiDiracOneHalfTeSCA FermiDiracMinusOne, Blakemore
    data.F                             .= Boltzmann

    #Here the user can specify, if they assume continuous or discontinuous charge carriers.
    data.isContinuous[iphin]            = true
    data.isContinuous[iphip]            = true

    # Following choices are possible for recombination model: bulk_recomb_model_none, bulk_recomb_model_trap_assisted, bulk_recomb_radiative, bulk_recomb_full <: bulk_recombination_model 
    data.bulk_recombination             = set_bulk_recombination(iphin = iphin, iphip = iphip, bulk_recombination_model = bulk_recombination)

    # Following choices are possible for boundary model: For contacts currently only ohmic_contact and schottky_contact are possible.
    # For inner boundaries we have interface_model_none, interface_model_surface_recombination, interface_model_ion_charge
    # (distinguish between left and right).
    data.boundary_type[bregionAcceptor]  = ohmic_contact
    data.boundary_type[bregionJunction1] = interface_model_surface_recombination
    data.boundary_type[bregionJunction2] = interface_model_surface_recombination                        
    data.boundary_type[bregionDonor]     = ohmic_contact   
    
    # Following choices are possible for the flux_discretization scheme: ScharfetterGummel, ScharfetterGummel_Graded,
    # excessChemicalPotential, excessChemicalPotential_Graded, diffusionEnhanced, generalized_SG
    data.flux_approximation              = excessChemicalPotential
    
    if test == false
        println("*** done\n")
    end

    ################################################################################
    if test == false
        println("Define ChargeTransportParams and fill in physical parameters")
    end
    ################################################################################

    # Params is a struct which contains all necessary physical parameters. If one wants to simulate
    # space-dependent variable, one additionally needs to generate a ParamsNodal struct, see Example102.
    params                                              = ChargeTransportParams(grid, numberOfCarriers)

    params.temperature                                  = T
    params.UT                                           = (kB * params.temperature) / q
    params.chargeNumbers[iphin]                         = -1
    params.chargeNumbers[iphip]                         =  1

    for ireg in 1:numberOfRegions           # interior region data

        params.dielectricConstant[ireg]                 = εr

        # effective DOS, band-edge energy and mobilities
        params.densityOfStates[iphin, ireg]             = Nc
        params.densityOfStates[iphip, ireg]             = Nv
        params.bandEdgeEnergy[iphin, ireg]              = Ec
        params.bandEdgeEnergy[iphip, ireg]              = Ev
        params.mobility[iphin, ireg]                    = mun
        params.mobility[iphip, ireg]                    = mup

        # recombination parameters
        params.recombinationRadiative[ireg]             = Radiative
        params.recombinationSRHLifetime[iphin, ireg]    = SRH_LifeTime
        params.recombinationSRHLifetime[iphip, ireg]    = SRH_LifeTime
        params.recombinationSRHTrapDensity[iphin, ireg] = SRH_TrapDensity
        params.recombinationSRHTrapDensity[iphip, ireg] = SRH_TrapDensity
        params.recombinationAuger[iphin, ireg]          = Auger
        params.recombinationAuger[iphip, ireg]          = Auger

    end

    for ibreg in 1:2   # outer boundary region data

        params.bDensityOfStates[iphin, ibreg]           = Nc
        params.bDensityOfStates[iphip, ibreg]           = Nv
        params.bBandEdgeEnergy[iphin, ibreg]            = Ec
        params.bBandEdgeEnergy[iphip, ibreg]            = Ev
    end
 
    ## inner boundary region data
    # params.bDensityOfStates[iphin, bregionJunction1]    = Nc
    # params.bDensityOfStates[iphip, bregionJunction1]    = Nv
 
    # params.bDensityOfStates[iphin, bregionJunction2]    = Nc
    # params.bDensityOfStates[iphip, bregionJunction2]    = Nv
 
    params.bBandEdgeEnergy[iphin, bregionJunction1]     = Ec 
    params.bBandEdgeEnergy[iphip, bregionJunction1]     = Ev 
 
    params.bBandEdgeEnergy[iphin, bregionJunction2]     = Ec 
    params.bBandEdgeEnergy[iphip, bregionJunction2]     = Ev 
 
    #######################
    params.bDensityOfStates[iphin, bregionJunction1]    = 2^(1/3) * ( Nc )^(2/3)
    params.bDensityOfStates[iphip, bregionJunction1]    = 2^(1/3) * ( Nv )^(2/3)
 
    params.bDensityOfStates[iphin, bregionJunction2]    = 2^(1/3) * ( Nc )^(2/3)
    params.bDensityOfStates[iphip, bregionJunction2]    = 2^(1/3) * ( Nv )^(2/3)
 
 
 
    # for surface recombination
    velocity = 1.0e15  * cm / s
    params.recombinationSRHvelocity[iphin, bregionJunction1]     = velocity
    params.recombinationSRHvelocity[iphip, bregionJunction1]     = velocity
 
    params.recombinationSRHvelocity[iphin, bregionJunction2]     = velocity
    params.recombinationSRHvelocity[iphip, bregionJunction2]     = velocity
 
    ##############################################################
    # params.bRecombinationSRHTrapDensity[iphin, bregionJunction1] = SRH_TrapDensity
    # params.bRecombinationSRHTrapDensity[iphip, bregionJunction1] = SRH_TrapDensity

    # params.bRecombinationSRHTrapDensity[iphin, bregionJunction2] = SRH_TrapDensity
    # params.bRecombinationSRHTrapDensity[iphip, bregionJunction2] = SRH_TrapDensity

    params.bRecombinationSRHTrapDensity[iphin, bregionJunction1] = 2^(1/3) * (SRH_TrapDensity )^(2/3)
    params.bRecombinationSRHTrapDensity[iphip, bregionJunction1] = 2^(1/3) * (SRH_TrapDensity )^(2/3)

    params.bRecombinationSRHTrapDensity[iphin, bregionJunction2] = 2^(1/3) * (SRH_TrapDensity )^(2/3)
    params.bRecombinationSRHTrapDensity[iphip, bregionJunction2] = 2^(1/3) * (SRH_TrapDensity )^(2/3)


    # interior doping
    params.doping[iphin, regionDonor]                   = Nd        # data.doping   = [0.0  Na;
    params.doping[iphin, regionIntrinsic]               = ni        #                  ni   0.0;
    params.doping[iphip, regionIntrinsic]               = 0.0       #                  Nd  0.0]
    params.doping[iphip, regionAcceptor]                = Na

    # boundary doping
    params.bDoping[iphin, bregionDonor]                 = Nd        # data.bDoping  = [0.0  Na;
    params.bDoping[iphip, bregionAcceptor]              = Na        #                  Nd  0.0]

    # Region dependent params is now a substruct of data which is again a substruct of the system and will be parsed 
    # in next step.
    data.params                                         = params

    # in the last step, we initialize our system with previous data which is likewise dependent on the parameters. 
    # important that this is in the end, otherwise our VoronoiFVMSys is not dependent on the data we initialized
    # but rather on default data.
    ctsys                                               = ChargeTransportSystem(grid, data, unknown_storage=unknown_storage)

    if test == false
        # show region dependent physical parameters. show_params() only supports region dependent parameters, but, if one wishes to
        # print nodal dependent parameters, currently this is possible with println(ctsys.data.paramsnodal). We neglected here, since
        # in most applications where the numberOfNodes is >> 10 this would results in a large output in the terminal.
        show_params(ctsys)
        println("*** done\n")
    end

    ################################################################################
    if test == false
        println("Define outerior boundary conditions")
    end
    ################################################################################

    # set ohmic contacts for each charge carrier at all outerior boundaries. First, 
    # we compute equilibrium solutions. Hence the boundary values at the ohmic contacts
    # are zero.
    set_ohmic_contact!(ctsys, bregionAcceptor, 0.0)
    set_ohmic_contact!(ctsys, bregionDonor, 0.0)

    if test == false
        println("*** done\n")
    end

    ################################################################################
    if test == false
        println("Define control parameters for Newton solver")
    end
    ################################################################################

    control                   = NewtonControl()
    control.verbose           = verbose
    control.damp_initial      = 0.5
    control.damp_growth       = 1.21
    control.max_iterations    = 250
    control.tol_absolute      = 1.0e-14
    control.tol_relative      = 1.0e-14
    control.handle_exceptions = true
    control.tol_round         = 1.0e-8
    control.max_round         = 5

    if test == false
        println("*** done\n")
    end

    ################################################################################
    if test == false
        println("Compute solution in thermodynamic equilibrium")
    end
    ################################################################################

    control.damp_initial  = 0.5
    control.damp_growth   = 1.2 # >= 1
    control.max_round     = 3

    # initialize solution and starting vectors
    initialGuess          = unknowns(ctsys)
    solution              = unknowns(ctsys)

    solution              = equilibrium_solve!(ctsys, control = control, nonlinear_steps = 20)

    initialGuess         .= solution 
    
    if test == false
        println("*** done\n")
    end
    ################################################################################
    if test == false
        println("Bias loop")
    end
    ################################################################################

    ctsys.data.calculation_type      = outOfEquilibrium

    if !(data.F == Boltzmann) # adjust control, when not using Boltzmann
        control.damp_initial      = 0.5
        control.damp_growth       = 1.2
        control.max_iterations    = 30
    end

    maxBias    = voltageAcceptor # bias goes until the given contactVoltage at acceptor boundary
    biasValues = range(0, stop = maxBias, length = 32)
    IV         = zeros(0)

    w_device = 0.5    * μm  # width of device
    z_device = 1.0e-4 * cm  # depth of device

    for Δu in biasValues

        #if verbose
        println("Δu  = ", Δu )
        #end
        # set non equilibrium boundary conditions
        set_ohmic_contact!(ctsys, bregionAcceptor, Δu)

        solve!(solution, initialGuess, ctsys, control = control, tstep = Inf)

        initialGuess .= solution

        # get I-V data
        #current = get_current_val(ctsys, solution)

        #push!(IV,  abs.(w_device * z_device * ( current)) )



    end # bias loop

    #writedlm("PIN-sol-with-surface-reco-2D-dens-bulk-statistics-velocity-$(params.recombinationSRHvelocity[iphin, bregionJunction1]).dat", [coord solution'])

    if test == false
        println("*** done\n")
    end
    # plot solution and IV curve
    if plotting
        #plot_energies(Plotter, grid, data, solution, "Applied voltage Δu = $(biasValues[end])", plotGridpoints = false)
        #Plotter.figure()
        plot_solution(Plotter, grid, data, solution, "Applied voltage Δu = $(biasValues[end])", plotGridpoints = true)
        PyPlot.axvline(h_pdoping, color="black", linestyle="solid")
        PyPlot.axvline(h_pdoping + h_intrinsic, color="black", linestyle="solid")
        Plotter.figure()
        plot_densities(Plotter, grid, data, solution, "Applied voltage Δu = $(biasValues[end])", plotGridpoints = false)
        #PyPlot.ylim(2.1813e6, 2.1814e6)
        PyPlot.axvline(h_pdoping, color="black", linestyle="solid")
        PyPlot.axvline(h_pdoping + h_intrinsic, color="black", linestyle="solid")
        #Plotter.figure()
        #plot_IV(Plotter, biasValues,IV, biasValues[end], plotGridpoints = true)
    end

    etan = zeros(length(coord))
    etap = zeros(length(coord))
    for xx = 1:length(coord)

        etan[xx] = params.chargeNumbers[iphin] / params.UT * ( (solution[iphin,xx] - solution[3,xx]) + params.bandEdgeEnergy[iphin, 1] / q )

        etap[xx] = params.chargeNumbers[iphip] / params.UT * ( (solution[iphip,xx] - solution[3,xx]) + params.bandEdgeEnergy[iphip, 1] / q )

    end
    println(length(coord))
    println(length(etan))

    PyPlot.figure()
    PyPlot.plot(coord, etan', color = "green", label = "\$\\eta_n\$"  )
    PyPlot.plot(coord, etap', color = "red", label = "\$\\eta_p\$" )
    PyPlot.axvline(h_pdoping, color="black", linestyle="solid")
    PyPlot.axvline(h_pdoping + h_intrinsic, color="black", linestyle="solid")
    PyPlot.title("Argument statistics function")
    Plotter.grid()
    PyPlot.legend(fancybox = true, loc = "best")



    testval = VoronoiFVM.norm(ctsys.fvmsys, solution, 2)
    return testval

    if test == false
        println("*** done\n")
    end

end #  main

function test()
    testval = 1.5192711281757634
    main(test = true, unknown_storage=:dense) ≈ testval && main(test = true, unknown_storage=:sparse) ≈ testval
end

if test == false
    println("This message should show when the PIN module has successfully recompiled.")
end

end # module