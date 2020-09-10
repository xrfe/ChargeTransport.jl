"""
Simulating charge transport in a perovskite solar cell (PSC)
without interfacial recombination.

"""
# Simulation values are from
# https://github.com/barnesgroupICL/Driftfusion/blob/master/Input_files/Evidence_for_ion_migration_SRH.csv

module PSC

using VoronoiFVM
using ChargeTransportInSolids
using ExtendableGrids
using PyPlot; PyPlot.pygui(true)
using Printf

function main(;n = 7, pyplot = false, verbose = false, dense = true)

    # close all windows
    PyPlot.close("all")

    ################################################################################
    println("Set up grid and regions")
    ################################################################################

    # region numbers
    regionDonor     = 1                           # n doped region
    regionIntrinsic = 2                           # intrinsic region
    regionAcceptor  = 3                           # p doped region
    regions         = [regionDonor, regionIntrinsic, regionAcceptor]

    # boundary region numbers
    bregionDonor    = 1
    bregionAcceptor = 2
    bregions        = [bregionDonor, bregionAcceptor]

    # grid
    # NB: Using geomspace to create uniform mesh is not a good idea. It may create virtual duplicates at boundaries.
    h_ndoping       = 0.2 * μm
    h_intrinsic     = 0.4 * μm
    h_pdoping       = 0.2 * μm
    x0              = 0.0 * μm 
    δ               = 4*n        # the larger, the finer the mesh
    t               = 0.2*μm/δ   # tolerance for geomspace and glue (with factor 10)
    k               = 1.5        # the closer to 1, the closer to the boundary geomspace works

    coord_n_u       = collect(range(x0, h_ndoping/2, step=h_ndoping/(δ)))
    coord_n_g       = geomspace(h_ndoping/2, 
                                h_ndoping, 
                                h_ndoping/(δ), 
                                h_ndoping/(2δ), 
                                tol=t)
    coord_i_g1      = geomspace(h_ndoping, 
                                h_ndoping+h_intrinsic/k, 
                                h_intrinsic/(4δ), 
                                h_intrinsic/(2δ), 
                                tol=t)
    coord_i_g2      = geomspace(h_ndoping+h_intrinsic/k, 
                                h_ndoping+h_intrinsic,               
                                h_intrinsic/(2δ),    
                                h_intrinsic/(4δ), 
                                tol=t)
    coord_p_g       = geomspace(h_ndoping+h_intrinsic,               
                                h_ndoping+h_intrinsic+h_pdoping/2, 
                                h_pdoping/(2δ),   
                                h_pdoping/(1δ),      
                                tol=t)
    coord_p_u       = collect(range(h_ndoping+h_intrinsic+h_pdoping/2, h_ndoping+h_intrinsic+h_pdoping, step=h_pdoping/(δ)))

    coord           = glue(coord_n_u,coord_n_g,  tol=10*t)
    coord           = glue(coord,    coord_i_g1, tol=10*t)
    coord           = glue(coord,    coord_i_g2, tol=10*t)
    coord           = glue(coord,    coord_p_g,  tol=10*t)
    coord           = glue(coord,    coord_p_u,  tol=10*t)
    grid            = ExtendableGrids.simplexgrid(coord)
    numberOfNodes   = length(coord)

    # set different regions in grid, doping profiles do not intersect
    cellmask!(grid, [0.0 * μm],                [h_ndoping],                           regionDonor)     # n-doped region   = 1
    cellmask!(grid, [h_ndoping],               [h_ndoping + h_intrinsic],             regionIntrinsic) # intrinsic region = 2
    cellmask!(grid, [h_ndoping + h_intrinsic], [h_ndoping + h_intrinsic + h_pdoping], regionAcceptor)  # p-doped region   = 3

    if pyplot
        ExtendableGrids.plot(ExtendableGrids.simplexgrid(coord, collect(0.0 : 0.25*μm : 0.5*μm)), Plotter = PyPlot, p = PyPlot.plot()) 
        PyPlot.title("Grid")
        PyPlot.figure()
    end
    println("*** done\n")
    ################################################################################
    println("Define physical parameters and model")
    ################################################################################

    # indices
    iphin, iphip, ipsi        = 1:3
    species                   = [iphin, iphip, ipsi]
    # iphin, iphip, iphia, ipsi = 1:4
    # species         = [iphin, iphip, iphia, ipsi]

    # number of (boundary) regions and carriers
    numberOfRegions         = length(regions)
    numberOfBoundaryRegions = length(bregions) 
    numberOfSpecies         = length(species)

    # temperature
    T    = 300.0                *  K

    # band edge energies    
    Eref =  5.4        *  eV # reference energy       
    Ec_d = -3.8        *  eV 
    Ev_d = -5.4        *  eV 

    Ec_i = -3.8        *  eV 
    Ev_i = -5.4        *  eV 
    Ea_i = -1.8        *  eV 

    Ec_a = -3.8        *  eV 
    Ev_a = -5.4        *  eV 

    EC   = [Ec_d, Ec_i, Ec_a] 
    EV   = [Ev_d, Ev_i, Ev_a] 
    EA   = [0.0,  Ea_i, 0.0] 

    # effective densities of state
    Nc       = 1.0e20               / (cm^3)
    Nv       = 1.0e20               / (cm^3)
    Nanion   = 1.0e19               / (cm^3)

    NC   = [Nc, Nc, Nc]
    NV   = [Nv, Nv, Nv]
    NA   = [0.0, Nanion, 0.0]

    # mobilities 
    μn_d = 20.0                 * (cm^2) / (V * s) 
    μp_d = 20.0                 * (cm^2) / (V * s) 

    μn_i = 20.0                 * (cm^2) / (V * s)  
    μp_i = 20.0                 * (cm^2) / (V * s)  
    μa_i = 1.0e-10              * (cm^2) / (V * s)

    μn_a = 20.0                 * (cm^2) / (V * s)  
    μp_a = 20.0                 * (cm^2) / (V * s)  
 
    μn   = [μn_d, μn_i, μn_a] 
    μp   = [μp_d, μp_i, μp_a] 
    μa   = [0.0,  μa_i, 0.0] 

    # relative dielectric permittivity  
    ε_d  = 20.0                 *  1.0    
    ε_i  = 20.0                 *  1.0 
    ε_a  = 20.0                 *  1.0  
    
    ε   = [ε_d, ε_i, ε_a] 

    # radiative recombination
    r0_d = 1.0e-10              * cm^3 / s
    r0_i = 1.0e-10              * cm^3 / s  
    r0_a = 1.0e-10              * cm^3 / s 

    r0   = [r0_d, r0_i, r0_a]

    # life times and trap densities (these values are from code)
    τn_d = 2.0e-31              * s
    τp_d = 2.0e-31              * s

    τn_i = 1.0e6                * s
    τp_i = 1.0e6               * s
    τn_a = τn_d
    τp_a = τp_d

    τn   = [τn_d, τn_i, τn_a]
    τp   = [τp_d, τp_i, τp_a]

    # SRH trap energies (needed for calculation of recombinationSRHTrapDensity)
    Ei_d = -5.2                 * eV   
    Ei_i = -4.6                 * eV 
    Ei_a = -4.0                 * eV

    # Ei_d = -4.6                 * eV   
    # Ei_i = -4.6                 * eV 
    # Ei_a = -4.6                 * eV

    EI   = [Ei_d, Ei_i, Ei_a]

    # Auger recombination
    Auger = 0.0

    # generation (only intrinsically present)
    generation_d = 0.0
    generation_i = 2.5e21 / (cm^3 * s)
    generation_a = 0.0
    generationEmittedLight = [generation_d, generation_i, generation_a]

    # doping (doping values are from Phils paper, not stated in the parameter list online)
    Nd             =   3.0e17   / (cm^3) 
    Na             =   3.0e17   / (cm^3) 
    C0             =   1.0e19   / (cm^3) 
    

    # intrinsic concentration (not doping!)
    ni             =   sqrt(Nc * Nv) * exp(-(Ec_i - Ev_i) / (2 * kB * T)) #/ (cm^3)

    # contact voltages
    voltageDonor     = 0.0 * V
    voltageAcceptor  = 1.1 * V 

    println("*** done\n")

    ################################################################################
    println("Define ChargeTransport data and fill in previously defined data")
    ################################################################################

    # initialize ChargeTransport instance
    data      = ChargeTransportInSolids.ChargeTransportData(numberOfNodes, numberOfRegions, numberOfBoundaryRegions, numberOfSpecies)

    # region independent data
    data.F                              .= Boltzmann # Boltzmann, FermiDiracOneHalf, Blakemore
    data.temperature                     = T
    data.UT                              = (kB * data.temperature) / q
    data.contactVoltage[bregionDonor]    = voltageDonor
    data.contactVoltage[bregionAcceptor] = voltageAcceptor
    data.chargeNumbers[iphin]            = -1
    data.chargeNumbers[iphip]            =  1
    #data.chargeNumbers[iphia]            =  1
    data.Eref                            =  Eref


    # boundary region data
    for ibreg in bregions
        data.bDensityOfStates[ibreg,iphin] = Nc
        data.bDensityOfStates[ibreg,iphip] = Nv
        #data.bDensityOfStates[ibreg,iphia] = 0.0

    end

    data.bBandEdgeEnergy[bregionDonor,iphin]     = Ec_d + data.Eref
    data.bBandEdgeEnergy[bregionDonor,iphip]     = Ev_d + data.Eref
    #data.bBandEdgeEnergy[bregionDonor,iphia]     = 0.0 + data.Eref
    data.bBandEdgeEnergy[bregionAcceptor,iphin]  = Ec_a + data.Eref
    data.bBandEdgeEnergy[bregionAcceptor,iphip]  = Ev_a + data.Eref
    #data.bBandEdgeEnergy[bregionAcceptor,iphia]  = 0.0  + data.Eref

    # interior region data
    for ireg in 1:numberOfRegions

        data.dielectricConstant[ireg]    = ε[ireg]

        # dos, band edge energy and mobilities
        data.densityOfStates[ireg,iphin] = NC[ireg]
        data.densityOfStates[ireg,iphip] = NV[ireg]
        #data.densityOfStates[ireg,iphia] = NA[ireg]

        data.bandEdgeEnergy[ireg,iphin]  = EC[ireg] + data.Eref
        data.bandEdgeEnergy[ireg,iphip]  = EV[ireg] + data.Eref
        #data.bandEdgeEnergy[ireg,iphia]  = EA[ireg] + data.Eref
        data.mobility[ireg,iphin]        = μn[ireg]
        data.mobility[ireg,iphip]        = μp[ireg]
        #data.mobility[ireg,iphia]        = μa[ireg]

        # recombination parameters
        data.recombinationRadiative[ireg]            = r0[ireg]
        data.recombinationSRHLifetime[ireg,iphin]    = τn[ireg]
        data.recombinationSRHLifetime[ireg,iphip]    = τp[ireg]
        data.recombinationSRHTrapDensity[ireg,iphin] = ChargeTransportInSolids.trapDensity(iphin, ireg, data, EI[ireg])
        data.recombinationSRHTrapDensity[ireg,iphip] = ChargeTransportInSolids.trapDensity(iphip, ireg, data, EI[ireg])
        data.recombinationAuger[ireg,iphin]          = Auger
        data.recombinationAuger[ireg,iphip]          = Auger

        data.generationEmittedLight[ireg]            = generationEmittedLight[ireg]

    end

    # interior doping
    data.doping[regionDonor,iphin]      = Nd        # data.doping   = [Nd  0.0  0.0;                   
    #data.doping[regionDonor,iphia]      = 0.0       #                  ni   ni  C0; 
    data.doping[regionIntrinsic,iphin]  = ni        #                  0.0  Na  0.0]
    data.doping[regionIntrinsic,iphip]  = ni        
    #data.doping[regionIntrinsic,iphia]  = C0        
    data.doping[regionAcceptor,iphip]   = Na
    #data.doping[regionAcceptor,iphia]   = 0.0

    # boundary doping
    data.bDoping[bregionDonor,iphin]    = Nd        # data.bDoping  = [Nd  0.0;
    data.bDoping[bregionAcceptor,iphip] = Na        #                  0.0  Na]

    # print data
    println(data)
    println("*** done\n")

    ################################################################################
    println("Define physics and system")
    ################################################################################

    ## initializing physics environment ##
    physics = VoronoiFVM.Physics(
    data        = data,
    num_species = numberOfSpecies,
    flux        = ChargeTransportInSolids.ScharfetterGummel!, #Sedan!, ScharfetterGummel!, diffusionEnhanced!, KopruckiGaertner!
    reaction    = ChargeTransportInSolids.reaction!,
    breaction   = ChargeTransportInSolids.breaction!
    )

    if dense
        sys = VoronoiFVM.System(grid, physics, unknown_storage = :dense)
    else
        sys = VoronoiFVM.System(grid, physics, unknown_storage = :sparse)
    end

    # enable all three species in all regions
    enable_species!(sys, ipsi,  regions)
    enable_species!(sys, iphin, regions)
    enable_species!(sys, iphip, regions)
    #enable_species!(sys, iphia, [regionIntrinsic])

    sys.boundary_values[iphin,  bregionDonor]    = data.contactVoltage[bregionDonor]
    sys.boundary_factors[iphin, bregionDonor]    = VoronoiFVM.Dirichlet

    sys.boundary_values[iphin,  bregionAcceptor] = data.contactVoltage[bregionAcceptor]
    sys.boundary_factors[iphin, bregionAcceptor] = VoronoiFVM.Dirichlet

    sys.boundary_values[iphip,  bregionDonor]    = data.contactVoltage[bregionDonor]
    sys.boundary_factors[iphip, bregionDonor]    = VoronoiFVM.Dirichlet

    sys.boundary_values[iphip,  bregionAcceptor] = data.contactVoltage[bregionAcceptor]
    sys.boundary_factors[iphip, bregionAcceptor] = VoronoiFVM.Dirichlet

    # sys.boundary_values[iphia,  bregionDonor]    = 0.0 * V
    # sys.boundary_factors[iphia, bregionDonor]    = VoronoiFVM.Dirichlet

    # sys.boundary_values[iphia,  bregionAcceptor] = 0.0 * V
    # sys.boundary_factors[iphia, bregionAcceptor] = VoronoiFVM.Dirichlet

    println("*** done\n")


    ################################################################################
    println("Define control parameters for Newton solver")
    ################################################################################

    control = VoronoiFVM.NewtonControl()
    control.verbose           = verbose
    control.max_iterations    = 50
    control.tol_absolute      = 1.0e-14
    control.tol_relative      = 1.0e-14
    control.handle_exceptions = true
    control.tol_round         = 1.0e-14
    control.max_round         = 5

    println("*** done\n")

    ################################################################################
    println("Compute solution in thermodynamic equilibrium for Boltzmann")
    ################################################################################

    data.inEquilibrium = true

    # initialize solution and starting vectors
    initialGuess                   = unknowns(sys)
    solution                       = unknowns(sys)
    @views initialGuess[ipsi,  :] .= 0.0
    @views initialGuess[iphin, :] .= 0.0
    @views initialGuess[iphip, :] .= 0.0
    #@views initialGuess[iphia, :] .= 0.0

    control.damp_initial      = 0.4
    control.damp_growth       = 1.21 # >= 1
    control.max_round         = 5

    sys.boundary_values[iphin, bregionAcceptor] = 0.0 * V
    sys.boundary_values[iphip, bregionAcceptor] = 0.0 * V
    #sys.boundary_values[iphia, bregionAcceptor]  = 0.0 * V
    sys.physics.data.contactVoltage             = 0.0 * sys.physics.data.contactVoltage

    I = collect(20.0:-1:0.0)
    LAMBDA = 10 .^ (-I) 
    prepend!(LAMBDA,0.0)

    for i in 1:length(LAMBDA)
        println("λ1 = $(LAMBDA[i])")
        sys.physics.data.λ1 = LAMBDA[i]
        solve!(solution, initialGuess, sys, control = control, tstep=Inf)
        initialGuess .= solution
        PyPlot.clf()
    end

    # if pyplot
    #     ChargeTransportInSolids.plotDensities(grid, data, solution, "EQUILIBRIUM")
    #     PyPlot.figure()
    #     ChargeTransportInSolids.plotEnergies(grid, data, solution, "EQUILIBRIUM")
    #     PyPlot.figure()
    #     ChargeTransportInSolids.plotSolution(coord, solution, data.Eref, "EQUILIBRIUM")
    # end

    println("*** done\n")

    ################################################################################
    println("Bias loop")
    ################################################################################

    data.inEquilibrium = false

    control.damp_initial      = 0.5
    control.damp_growth       = 1.2 # >= 1
    control.max_round         = 7

    # set non equilibrium boundary conditions
    sys.physics.data.contactVoltage[bregionDonor]    = voltageDonor
    sys.physics.data.contactVoltage[bregionAcceptor] = voltageAcceptor
    sys.boundary_values[iphin, bregionAcceptor]      = data.contactVoltage[bregionAcceptor]
    sys.boundary_values[iphip, bregionAcceptor]      = data.contactVoltage[bregionAcceptor]

    maxBias    = data.contactVoltage[bregionAcceptor]
    biasValues = range(0, stop = maxBias, length = 41)
    IV         = zeros(0)

    w_device = 0.5 * μm     # width of device
    z_device = 1.0e-4 * cm  # depth of device


    for Δu in biasValues

        println("Bias value: Δu = $(Δu) (no illumination)")

        data.contactVoltage[bregionAcceptor] = Δu
        sys.boundary_values[iphin, bregionAcceptor] = Δu
        sys.boundary_values[iphip, bregionAcceptor] = Δu

        solve!(solution, initialGuess, sys, control = control, tstep = Inf)

        initialGuess .= solution

        # get IV curve
        factory = VoronoiFVM.TestFunctionFactory(sys)

        # testfunction zero in bregionAcceptor and one in bregionDonor
        tf     = testfunction(factory, [bregionAcceptor], [bregionDonor])
        I      = integrate(sys, tf, solution)

        push!(IV,  abs.(w_device * z_device * (I[iphin] + I[iphip])))

        # plotting
        if pyplot
            if Δu == maxBias
            ChargeTransportInSolids.plotDensities(grid, data, solution, "$Δu (no illumination)")
            PyPlot.figure()
            ChargeTransportInSolids.plotEnergies(grid, data, solution, "$Δu (no illumination)")
            PyPlot.figure()
            ChargeTransportInSolids.plotSolution(coord, solution, data.Eref, "$Δu (no illumination)")
            end
        end


    end # bias loop

    # return IV
    println("*** done\n")

    ################################################################################
    println("Illumination loop")
    ################################################################################ 

    I = collect(20.0:-1:0.0)
    LAMBDA = 10 .^ (-I) 
    prepend!(LAMBDA,0.0)

    for i in 1:length(LAMBDA)
        println("λ2 = $(LAMBDA[i])")
        sys.physics.data.λ2 = LAMBDA[i]
        solve!(solution, initialGuess, sys, control = control, tstep=Inf)
        initialGuess = solution
    end

    if pyplot
        PyPlot.figure()
        ChargeTransportInSolids.plotDensities(grid, data, solution, "$(maxBias) (illuminated)")
        PyPlot.figure()
        ChargeTransportInSolids.plotEnergies(grid, data, solution, "$(maxBias) (illuminated)")
        PyPlot.figure()
        ChargeTransportInSolids.plotSolution(coord, solution, data.Eref, "$(maxBias) (illuminated)")
    end

    println("*** done\n")


    # ################################################################################
    # println("Transient solution")
    # ################################################################################

    # tstep = 0.5*1e-16
    # tstep_max = 0.5*1e0
    # dV = 0.25


    #  # Solve the stationary state system
    # control=VoronoiFVM.NewtonControl()
    # control.Δt=tstep
    # control.Δt_max=tstep_max
    # control.Δt_grow=1.5
    # control.Δu_opt=dV
    # control.verbose=false
    # control.max_lureuse=0
    # control.edge_cutoff=1.0e-16

    # # inival.=initial_solution
    # initial_solution[1:2,2:end-1].=0.0
    # println(initial_solution)
    # sampling_times=[t for t in 0.0:1e-1:1e1]

    # solution_transient = unknowns(sys)

    # evolve!(solution_transient,initial_solution,sys,sampling_times, control=control)

    # ChargeTransportInSolids.plotDensities(grid, data, solution_transient, "FINAL")

    # PyPlot.figure()
    # ChargeTransportInSolids.plotEnergies(grid, data, solution_transient, "FINAL")

    # println("*** done\n")

    # return solution_transient



    

end #  main

println("This message should show when the PSC module is successfully recompiled.")

end # module


#     # Number of periods to run
#     nper=1

#     # Number of samples per period
#     nsamp=4
#     ###############################################################

#     # BV kinetic constants
#     phi_min=0*V
#     phi_max=-1.6*V

#     # Scan rate
#     scan=scan_rate*mV/s

#     per=2*abs(phi_max-phi_min)/scan

#     sampling_times=[t for t in 0.0:0.5*per/nsamp:per*nper]


#             function pre(sol,time) # vielleich t nicht nötig bei uns
#             #theta=Nernst_const(time)
#             #omega=freq*2.0*π
#             eplus,eminus=BV_rate_constants(time)
#         end
#         I_disk=[0.0,0.0]
#         I_disk_old=[0.0,0.0]
#         I_ring=[]
#         di=0.0
#         function delta(solution, oldsolution, time,tstep) # discrete Energie
#             I_disk=VoronoiFVM.integrate(rdcell,tfc_disk,solution,oldsolution,tstep)
#             I_ring=VoronoiFVM.integrate(rdcell,tfc_ring,solution,oldsolution,tstep)
#             di=FaradayConstant*abs(I_disk_old[specB]-I_disk[specB])/mA
#         end

        
#         function post(solution, oldsolution, time,tstep) # vielleich t nicht nötig bei uns, plotten
#             push!(vdisk,phi_cv(time))
#             push!(iring,-I_ring[specB]*FaradayConstant)
#             push!(idisk,I_disk[specB]*FaradayConstant)
#             push!(time_discretization,time)
#             if verbose
#                 ProgressMeter.next!(pmeter,showvalues=[
#                     (:Δϕ,phi_cv(time)),
#                     (:dI,di),
#                     (:t,time),
#                 ],valuecolor=:yellow)
#             end
#             I_disk_old=I_disk
#         end

# evolve!(solution,inival,sys,sampling_times, control=control, pre=pre,post=post,delta=delta)